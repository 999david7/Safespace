import Foundation

/// Reads and writes the encrypted vault file.
public struct VaultStorage: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Safespace/vault.dat`
    public static let `default` = VaultStorage(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Safespace", isDirectory: true)
            .appendingPathComponent("vault.dat")
    )

    /// File name used by Safespace 1.0 and 1.1, before the vault became `vault.dat`.
    public static let legacyFileName = "vault.safespace"

    public var backupURL: URL {
        url.appendingPathExtension("bak")
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Renames a vault left by an older version (`vault.safespace` and its `.bak`) to this
    /// storage's file name. Does nothing when this vault already exists or there is no old one.
    public func migrateLegacyFile() throws {
        let fm = FileManager.default
        let legacy = url.deletingLastPathComponent().appendingPathComponent(Self.legacyFileName)
        guard !exists, legacy != url, fm.fileExists(atPath: legacy.path) else { return }
        try fm.moveItem(at: legacy, to: url)
        let legacyBackup = legacy.appendingPathExtension("bak")
        if fm.fileExists(atPath: legacyBackup.path), !fm.fileExists(atPath: backupURL.path) {
            try? fm.moveItem(at: legacyBackup, to: backupURL)
        }
    }

    /// Makes `source` (a vault file from another Mac, a backup, an older version…) the vault here.
    /// Refuses files that aren't a Safespace vault, and never replaces an existing vault.
    public func adopt(_ source: URL) throws {
        guard !exists else { throw VaultError.vaultExists }
        let file = try VaultStorage(url: source).read()
        guard file.version <= VaultFile.currentVersion else { throw VaultError.unsupportedVersion(file.version) }
        guard file.kdf == VaultFile.kdfName, file.salt.count >= 16, file.iterations > 0 else {
            throw VaultError.corruptFile
        }
        try write(file)
    }

    public func read() throws -> VaultFile {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(VaultFile.self, from: data)
        } catch {
            throw VaultError.corruptFile
        }
    }

    public func write(_ file: VaultFile) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)

        // Keep the previous version around in case a write is ever interrupted or goes wrong.
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }

        try data.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
