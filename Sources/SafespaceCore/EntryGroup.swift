import Foundation

/// A user-defined, color-coded collection of logins ("Work", "Banking", …).
/// Each entry belongs to at most one group via `Entry.groupID`.
public struct EntryGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// sRGB color as 0xRRGGBB.
    public var color: UInt32

    public init(id: UUID = UUID(), name: String, color: UInt32 = EntryGroup.palette[0]) {
        self.id = id
        self.name = name
        self.color = color & 0xFFFFFF
    }

    /// Preset swatches offered when creating a group. Any other color can be picked too.
    public static let palette: [UInt32] = [
        0x3B7DD8, // blue
        0x0B8F57, // green
        0xD94B3D, // red
        0xE0A800, // amber
        0x8E5BD1, // purple
        0xE06C9F, // pink
        0x1AA3A3, // teal
        0xE0772B, // orange
        0x6B6B70, // graphite
    ]

    /// The first palette color not yet used by `existing`, so new groups are distinct by default.
    public static func suggestedColor(avoiding existing: [EntryGroup]) -> UInt32 {
        let used = Set(existing.map(\.color))
        return palette.first { !used.contains($0) } ?? palette[existing.count % palette.count]
    }
}
