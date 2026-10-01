import CryptoKit
import Foundation
import LocalAuthentication
import SafespaceCore
import Security

enum BiometricError: LocalizedError {
    case unavailable(String)
    case cancelled
    case lockedOut
    case invalidated
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .cancelled: "Touch ID was cancelled."
        case .lockedOut: "Touch ID is temporarily locked. Enter your master password."
        case .invalidated: "Touch ID unlock was turned off because your fingerprints or master password changed. Unlock with your password, then turn it back on in Settings."
        case .failed(let message): message
        }
    }
}

/// Touch ID unlock backed by the Secure Enclave.
///
/// The vault key is sealed (ECDH + HKDF + AES-GCM) to a P-256 key that lives inside this Mac's
/// Secure Enclave. That key is created with `.biometryCurrentSet`, so the enclave itself refuses to
/// use it without a successful fingerprint, and it becomes permanently unusable if fingerprints
/// are added or removed. The enrollment file alone is useless on any other machine.
struct BiometricUnlock {
    private struct Enrollment: Codable {
        var version: Int
        /// Secure Enclave–encrypted private key blob.
        var enclaveKey: Data
        var ephemeralPublicKey: Data
        /// AES-GCM box of the vault key, authenticated with the vault's salt.
        var sealedVaultKey: Data
    }

    let url: URL

    init(storage: VaultStorage) {
        url = storage.url.deletingLastPathComponent().appendingPathComponent("touchid.enrollment")
    }

    var isEnrolled: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// `nil` when Touch ID can be used, otherwise a user-facing explanation.
    static var unavailableReason: String? {
        guard SecureEnclave.isAvailable else { return "This Mac doesn't have a Secure Enclave." }
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if error?.code == LAError.biometryNotEnrolled.rawValue {
                return "Add a fingerprint in System Settings → Touch ID & Password first."
            }
            return "Touch ID isn't available on this Mac."
        }
        return nil
    }

    /// Asks for a fingerprint without releasing anything, e.g. to confirm turning the feature on.
    static func confirm(reason: String) async throws {
        do {
            _ = try await LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let error as LAError {
            throw map(error)
        }
    }

    /// Seals `vaultKey` to a new Secure Enclave key. Doesn't prompt; unsealing does.
    func enroll(vaultKey: SymmetricKey, salt: Data) throws {
        var cfError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], &cfError
        ) else {
            throw BiometricError.failed("Couldn't configure Touch ID protection.")
        }

        let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let ephemeral = P256.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: enclaveKey.publicKey)
        let rawKey = vaultKey.withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(rawKey, using: Self.wrappingKey(shared), authenticating: salt)
        guard let sealed = box.combined else { throw BiometricError.failed("Couldn't seal the vault key.") }

        let enrollment = Enrollment(
            version: 1,
            enclaveKey: enclaveKey.dataRepresentation,
            ephemeralPublicKey: ephemeral.publicKey.x963Representation,
            sealedVaultKey: sealed
        )
        try JSONEncoder().encode(enrollment).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Prompts for a fingerprint and returns the vault key. `salt` must match the current vault file.
    func unlock(salt: Data) async throws -> SymmetricKey {
        guard let data = try? Data(contentsOf: url),
              let enrollment = try? JSONDecoder().decode(Enrollment.self, from: data) else {
            throw BiometricError.invalidated
        }

        let context = LAContext()
        context.localizedFallbackTitle = "Use Master Password"
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "unlock your vault")
        } catch let error as LAError {
            throw Self.map(error)
        }

        do {
            // The authenticated context lets the enclave use the key without a second prompt.
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: enrollment.enclaveKey, authenticationContext: context
            )
            let ephemeral = try P256.KeyAgreement.PublicKey(x963Representation: enrollment.ephemeralPublicKey)
            let shared = try enclaveKey.sharedSecretFromKeyAgreement(with: ephemeral)
            let box = try AES.GCM.SealedBox(combined: enrollment.sealedVaultKey)
            let rawKey = try AES.GCM.open(box, using: Self.wrappingKey(shared), authenticating: salt)
            return SymmetricKey(data: rawKey)
        } catch {
            // Fingerprints changed (enclave key invalidated) or the vault was re-keyed.
            throw BiometricError.invalidated
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    private static func wrappingKey(_ shared: SharedSecret) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: shared),
            info: Data("safespace.touchid.v1".utf8),
            outputByteCount: 32
        )
    }

    private static func map(_ error: LAError) -> BiometricError {
        switch error.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback: .cancelled
        case .biometryLockout: .lockedOut
        case .biometryNotEnrolled, .biometryNotAvailable: .unavailable(unavailableReason ?? error.localizedDescription)
        default: .failed(error.localizedDescription)
        }
    }
}
