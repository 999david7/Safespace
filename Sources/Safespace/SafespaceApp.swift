import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless inside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Clipboard.clearIfOwned()
    }
}

@main
struct SafespaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: VaultStore
    @AppStorage(Preferences.appearance) private var appearance = "light"

    init() {
        #if DEBUG
        if let screen = ProcessInfo.processInfo.environment["SAFESPACE_DEMO"] {
            _store = State(initialValue: VaultStore.demo(screen: screen))
            return
        }
        #endif
        _store = State(initialValue: VaultStore())
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": .dark
        case "system": nil
        default: .light
        }
    }

    var body: some Scene {
        Window("Safespace", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Login") { store.newEntryRequested = true }
                    .keyboardShortcut("n")
                    .disabled(store.state != .unlocked)
            }
            CommandMenu("Vault") {
                Button("Password Generator") { store.showGenerator = true }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(store.state != .unlocked)
                Divider()
                Button("Lock Vault") { store.lock(manual: true) }
                    .keyboardShortcut("l")
                    .disabled(store.state != .unlocked)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .preferredColorScheme(colorScheme)
        }
    }
}
