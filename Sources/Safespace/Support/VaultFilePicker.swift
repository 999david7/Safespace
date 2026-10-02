import AppKit

enum VaultFilePicker {
    /// Asks for a Safespace vault file: `vault.dat`, or `vault.safespace` from older versions.
    @MainActor
    static func choose(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Safespace Vault"
        panel.message = "Pick a vault file: vault.dat, or vault.safespace from an older version of Safespace."
        panel.prompt = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
