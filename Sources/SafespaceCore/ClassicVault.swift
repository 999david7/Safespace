import CryptoKit
import Foundation

/// Reads `vault.dat` files written by the original SafeSpace (the C++ Windows app), which kept
/// them at `%APPDATA%\SafeSpace\vault.dat`, the same path the current Windows app uses.
///
/// Layout, all integers little-endian:
///
///     "SAFESPC\0"  8   magic
///     version      4
///     iterations   4
///     salt        16
///     nonce       12
///     tag         16
///     length       4   ciphertext byte count
///     ciphertext   N   AES-256-GCM, no associated data
///
/// The key is PBKDF2-HMAC-SHA256 over the UTF-8 master password, like ours. The plaintext is
/// `count u32, nextID u32`, then per entry `id u32`, five length-prefixed UTF-8 strings
/// (service, username, password, category, notes) and `created i64, updated i64` in Unix seconds.
public enum ClassicVault {
    static let magic = Data("SAFESPC\0".utf8)
    static let supportedVersion: UInt32 = 1
    static let headerLength = 8 + 4 + 4 + 16 + 12 + 16 + 4

    /// One login as the original app stores it.
    public struct Record: Equatable, Sendable {
        public var service: String
        public var username: String
        public var password: String
        public var category: String
        public var notes: String
        public var created: Date
        public var updated: Date

        public init(service: String, username: String = "", password: String = "", category: String = "",
                    notes: String = "", created: Date = Date(), updated: Date = Date()) {
            self.service = service
            self.username = username
            self.password = password
            self.category = category
            self.notes = notes
            self.created = created
            self.updated = updated
        }
    }

    /// Whether `data` starts with the original SafeSpace signature.
    public static func isClassic(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    /// Checks the header without decrypting, so a bad file is refused before asking for a password.
    public static func validate(_ data: Data) throws {
        _ = try Header(data)
    }

    /// Decrypts the file. Throws `VaultError.wrongPassword` when the tag doesn't verify.
    public static func decrypt(_ data: Data, password: String) throws -> [Record] {
        let header = try Header(data)
        let key = try Vault.deriveKey(password: password, salt: header.salt, iterations: header.iterations)

        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: header.nonce), ciphertext: header.ciphertext, tag: header.tag)
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw VaultError.wrongPassword
        }
        return try parse(plaintext)
    }

    /// Decrypts the file and converts it to Safespace logins; each distinct category becomes a group.
    public static func contents(of data: Data, password: String) throws -> VaultContents {
        convert(try decrypt(data, password: password))
    }

    static func convert(_ records: [Record]) -> VaultContents {
        var groups: [EntryGroup] = []
        let entries = records.map { record in
            let category = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            var groupID: UUID?
            if !category.isEmpty {
                if let match = groups.first(where: { $0.name.caseInsensitiveCompare(category) == .orderedSame }) {
                    groupID = match.id
                } else {
                    let group = EntryGroup(name: category, color: EntryGroup.suggestedColor(avoiding: groups))
                    groups.append(group)
                    groupID = group.id
                }
            }
            return Entry(
                title: record.service,
                username: record.username,
                password: record.password,
                notes: record.notes,
                groupID: groupID,
                createdAt: record.created,
                updatedAt: record.updated
            )
        }
        return VaultContents(entries: entries, groups: groups)
    }

    // MARK: - Parsing

    struct Header {
        var iterations: UInt32
        var salt: Data
        var nonce: Data
        var tag: Data
        var ciphertext: Data

        init(_ data: Data) throws {
            let data = Data(data) // rebase indices to 0
            guard data.count >= ClassicVault.headerLength, ClassicVault.isClassic(data) else {
                throw VaultError.corruptFile
            }
            var reader = Reader(data: data, position: 8)
            let version = try reader.u32()
            guard version <= ClassicVault.supportedVersion else { throw VaultError.unsupportedVersion(Int(version)) }
            iterations = try reader.u32()
            guard iterations > 0, iterations <= 50_000_000 else { throw VaultError.corruptFile }
            salt = try reader.bytes(16)
            nonce = try reader.bytes(12)
            tag = try reader.bytes(16)
            let length = Int(try reader.u32())
            guard reader.position + length == data.count else { throw VaultError.corruptFile }
            ciphertext = try reader.bytes(length)
        }
    }

    static func parse(_ plaintext: Data) throws -> [Record] {
        var reader = Reader(data: Data(plaintext), position: 0)
        let count = try reader.u32()
        _ = try reader.u32() // next id; ours are UUIDs
        var records: [Record] = []
        records.reserveCapacity(Int(min(count, 4096)))
        for _ in 0..<count {
            _ = try reader.u32() // id
            let service = try reader.string()
            let username = try reader.string()
            let password = try reader.string()
            let category = try reader.string()
            let notes = try reader.string()
            let created = try reader.i64()
            let updated = try reader.i64()
            records.append(Record(
                service: service, username: username, password: password, category: category, notes: notes,
                created: Date(timeIntervalSince1970: TimeInterval(created)),
                updated: Date(timeIntervalSince1970: TimeInterval(updated))
            ))
        }
        return records
    }

    /// Bounds-checked little-endian cursor; a hostile length can't walk it off the end.
    struct Reader {
        let data: Data
        var position: Int

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, count <= data.count - position else { throw VaultError.corruptFile }
            defer { position += count }
            return data.subdata(in: position..<position + count)
        }

        mutating func u32() throws -> UInt32 {
            try bytes(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func i64() throws -> Int64 {
            Int64(bitPattern: try bytes(8).reversed().reduce(0) { $0 << 8 | UInt64($1) })
        }

        mutating func string() throws -> String {
            let raw = try bytes(Int(try u32()))
            guard let string = String(data: raw, encoding: .utf8) else { throw VaultError.corruptFile }
            return string
        }
    }
}
