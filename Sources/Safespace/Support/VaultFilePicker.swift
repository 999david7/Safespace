import AppKit

enum VaultFilePicker {
    /// Asks for a Safespace vault file: `vault.dat` (including one from the original SafeSpace),
    /// or `vault.safespace` from older versions.
    @MainActor
    static func choose(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Safespace Vault"
        panel.message = "Pick a vault file: vault.dat (also from the original SafeSpace for Windows), or vault.safespace from an older version."
        panel.prompt = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
