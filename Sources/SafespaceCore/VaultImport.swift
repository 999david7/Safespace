import Foundation

/// What `VaultContents.merging(_:)` did with an imported vault.
public struct ImportSummary: Equatable, Sendable {
    public var added = 0
    /// Logins that already existed here (same id) and were newer in the imported file.
    public var updated = 0
    /// Logins already present, either the same login or an identical copy.
    public var skipped = 0
    public var groupsAdded = 0

    public init(added: Int = 0, updated: Int = 0, skipped: Int = 0, groupsAdded: Int = 0) {
        self.added = added
        self.updated = updated
        self.skipped = skipped
        self.groupsAdded = groupsAdded
    }

    /// "Imported 12 logins · 3 already here", for a toast or a settings message.
    public var message: String {
        let changed = added + updated
        var parts = ["Imported \(changed) \(changed == 1 ? "login" : "logins")"]
        if groupsAdded > 0 { parts.append("\(groupsAdded) new \(groupsAdded == 1 ? "group" : "groups")") }
        if skipped > 0 { parts.append("\(skipped) already here") }
        return parts.joined(separator: " · ")
    }
}

extension VaultContents {
    /// Adds the logins and groups of `imported` to this vault without losing anything here.
    ///
    /// - Groups match by id, then by name (case-insensitive); unmatched groups are added.
    /// - A login with an id that exists here replaces it only if the imported copy was edited later.
    /// - A login identical to one here (title, username, password and website) is skipped.
    public func merging(_ imported: VaultContents) -> (VaultContents, ImportSummary) {
        var result = self
        var summary = ImportSummary()

        var groupMap: [UUID: UUID] = [:]
        for group in imported.groups {
            if result.groups.contains(where: { $0.id == group.id }) {
                groupMap[group.id] = group.id
            } else if let match = result.groups.first(where: { $0.name.normalizedGroupName == group.name.normalizedGroupName }) {
                groupMap[group.id] = match.id
            } else {
                result.groups.append(group)
                groupMap[group.id] = group.id
                summary.groupsAdded += 1
            }
        }

        for var entry in imported.entries {
            entry.groupID = entry.groupID.flatMap { groupMap[$0] }
            if let index = result.entries.firstIndex(where: { $0.id == entry.id }) {
                if entry.updatedAt > result.entries[index].updatedAt {
                    result.entries[index] = entry
                    summary.updated += 1
                } else {
                    summary.skipped += 1
                }
            } else if result.entries.contains(where: { $0.isSameLogin(as: entry) }) {
                summary.skipped += 1
            } else {
                result.entries.append(entry)
                summary.added += 1
            }
        }
        return (result, summary)
    }
}

private extension String {
    var normalizedGroupName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension Entry {
    func isSameLogin(as other: Entry) -> Bool {
        title == other.title && username == other.username && password == other.password && url == other.url
    }
}
