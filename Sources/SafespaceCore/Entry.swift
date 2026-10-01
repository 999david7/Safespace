import Foundation

/// A single login stored in the vault.
public struct Entry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var username: String
    public var password: String
    public var url: String
    public var notes: String
    public var favorite: Bool
    /// The `EntryGroup` this login is filed under, if any.
    public var groupID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        username: String = "",
        password: String = "",
        url: String = "",
        notes: String = "",
        favorite: Bool = false,
        groupID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.username = username
        self.password = password
        self.url = url
        self.notes = notes
        self.favorite = favorite
        self.groupID = groupID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The host part of `url`, tolerant of missing schemes ("github.com/login" → "github.com").
    public var host: String? {
        websiteURL?.host()
    }

    /// `url` as an openable URL, adding `https://` when no scheme was typed.
    public var websiteURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return url
    }
}
