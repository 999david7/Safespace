import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum VaultError: LocalizedError, Equatable {
    case wrongPassword
    case corruptFile
    case unsupportedVersion(Int)
    case emptyPassword
    case keyDerivationFailed
    case vaultExists

    public var errorDescription: String? {
        switch self {
        case .wrongPassword: "Incorrect master password."
        case .corruptFile: "The vault file is damaged or unreadable."
        case .unsupportedVersion(let v): "This vault was created by a newer version of Safespace (format \(v))."
        case .emptyPassword: "The master password can't be empty."
        case .keyDerivationFailed: "Couldn't derive the encryption key."
        case .vaultExists: "A vault already exists on this Mac."
        }
    }
}

/// The on-disk representation. Everything except the KDF parameters is encrypted.
public struct VaultFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let kdfName = "PBKDF2-HMAC-SHA256"

    public var version: Int
    public var kdf: String
    public var iterations: UInt32
    public var salt: Data
    /// AES-256-GCM combined box: nonce ‖ ciphertext ‖ tag.
    public var ciphertext: Data

    /// Header fields are bound to the ciphertext as authenticated data so they can't be swapped.
    var associatedData: Data {
        Data("safespace|\(version)|\(kdf)|\(iterations)|\(salt.base64EncodedString())".utf8)
    }
}

/// Everything stored inside the encrypted payload.
public struct VaultContents: Equatable, Sendable {
    public var entries: [Entry]
    public var groups: [EntryGroup]

    public init(entries: [Entry] = [], groups: [EntryGroup] = []) {
        self.entries = entries
        self.groups = groups
    }
}

/// A vault whose key has been derived. Holding one means the vault is unlocked.
public struct UnlockedVault: Sendable {
    public let key: SymmetricKey
    public let salt: Data
    public let iterations: UInt32
}

public enum Vault {
    public static let defaultIterations: UInt32 = 600_000
    static let saltLength = 32

    private struct Payload: Codable {
        var entries: [Entry]
        /// Absent in vaults written before groups existed.
        var groups: [EntryGroup]?
    }

    /// Derives a fresh key (with a new random salt) for a new or re-keyed vault.
    public static func create(password: String, iterations: UInt32 = defaultIterations) throws -> UnlockedVault {
        let salt = randomData(count: saltLength)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        return UnlockedVault(key: key, salt: salt, iterations: iterations)
    }

    public static func encrypt(_ entries: [Entry], groups: [EntryGroup] = [], with vault: UnlockedVault) throws -> VaultFile {
        var file = VaultFile(
            version: VaultFile.currentVersion,
            kdf: VaultFile.kdfName,
            iterations: vault.iterations,
            salt: vault.salt,
            ciphertext: Data()
        )
        let plaintext = try JSONEncoder().encode(Payload(entries: entries, groups: groups))
        let box = try AES.GCM.seal(plaintext, using: vault.key, authenticating: file.associatedData)
        guard let combined = box.combined else { throw VaultError.corruptFile }
        file.ciphertext = combined
        return file
    }

    public static func decrypt(_ file: VaultFile, password: String) throws -> (UnlockedVault, [Entry]) {
        let (vault, contents) = try decryptContents(file, password: password)
        return (vault, contents.entries)
    }

    /// Opens the vault with an already-derived key (e.g. one released by Touch ID).
    public static func decrypt(_ file: VaultFile, key: SymmetricKey) throws -> (UnlockedVault, [Entry]) {
        let (vault, contents) = try decryptContents(file, key: key)
        return (vault, contents.entries)
    }

    public static func decryptContents(_ file: VaultFile, password: String) throws -> (UnlockedVault, VaultContents) {
        guard file.version <= VaultFile.currentVersion else { throw VaultError.unsupportedVersion(file.version) }
        guard file.kdf == VaultFile.kdfName, file.salt.count >= 16, file.iterations > 0 else {
            throw VaultError.corruptFile
        }
        let key = try deriveKey(password: password, salt: file.salt, iterations: file.iterations)
        return try decryptContents(file, key: key)
    }

    public static func decryptContents(_ file: VaultFile, key: SymmetricKey) throws -> (UnlockedVault, VaultContents) {
        guard file.version <= VaultFile.currentVersion else { throw VaultError.unsupportedVersion(file.version) }
        guard file.kdf == VaultFile.kdfName, file.salt.count >= 16, file.iterations > 0 else {
            throw VaultError.corruptFile
        }

        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: file.ciphertext)
            plaintext = try AES.GCM.open(box, using: key, authenticating: file.associatedData)
        } catch {
            // GCM authentication failure: wrong key or tampered data. Indistinguishable by design.
            throw VaultError.wrongPassword
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: plaintext) else {
            throw VaultError.corruptFile
        }
        // Drop links to groups that no longer exist so the UI never sees a dangling reference.
        let groups = payload.groups ?? []
        let groupIDs = Set(groups.map(\.id))
        var entries = payload.entries
        for index in entries.indices where entries[index].groupID.map({ !groupIDs.contains($0) }) ?? false {
            entries[index].groupID = nil
        }
        return (
            UnlockedVault(key: key, salt: file.salt, iterations: file.iterations),
            VaultContents(entries: entries, groups: groups)
        )
    }

    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        guard !passwordBytes.isEmpty else { throw VaultError.emptyPassword }
        guard !salt.isEmpty else { throw VaultError.keyDerivationFailed }

        var derived = [UInt8](repeating: 0, count: kCCKeySizeAES256)
        let derivedCount = derived.count
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                derived.withUnsafeMutableBytes { derivedBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress!.assumingMemoryBound(to: CChar.self), passwordBytes.count,
                        saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                        derivedBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), derivedCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.keyDerivationFailed }
        defer { derived.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        return SymmetricKey(data: derived)
    }

    static func randomData(count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        precondition(status == errSecSuccess, "System random number generator failed")
        return data
    }
}
