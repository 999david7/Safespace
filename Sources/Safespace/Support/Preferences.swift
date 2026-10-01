import Foundation

/// UserDefaults keys shared between `@AppStorage` views and non-view code.
enum Preferences {
    static let autoLockMinutes = "autoLockMinutes"
    static let lockOnSleep = "lockOnSleep"
    static let clipboardClearSeconds = "clipboardClearSeconds"
    static let appearance = "appearance"

    static func register() {
        UserDefaults.standard.register(defaults: [
            autoLockMinutes: 5,
            lockOnSleep: true,
            clipboardClearSeconds: 30,
            appearance: "light",
        ])
    }
}
