import AppKit

enum Clipboard {
    /// Tells well-behaved clipboard managers not to record the item (nspasteboard.org convention).
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static var ownedChangeCount: Int?

    static func copy(_ value: String, clearAfter seconds: Int) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString(value, forType: .string)
        pasteboard.setData(Data(), forType: concealed)

        let changeCount = pasteboard.changeCount
        ownedChangeCount = changeCount
        guard seconds > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            // Only clear if the user hasn't copied something else in the meantime.
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                ownedChangeCount = nil
            }
        }
    }

    static func clearIfOwned() {
        let pasteboard = NSPasteboard.general
        if let owned = ownedChangeCount, pasteboard.changeCount == owned {
            pasteboard.clearContents()
        }
        ownedChangeCount = nil
    }
}
