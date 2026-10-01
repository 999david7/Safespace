import Foundation

/// Reads and writes the encrypted vault file.
public struct VaultStorage: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/Safespace/vault.safespace`
    public static let `default` = VaultStorage(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Safespace", isDirectory: true)
            .appendingPathComponent("vault.safespace")
    )

    public var backupURL: URL {
        url.appendingPathExtension("bak")
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
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
