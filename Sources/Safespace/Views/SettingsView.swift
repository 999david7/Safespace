import SafespaceCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SecuritySettings()
                .tabItem { Label("Security", systemImage: "lock.shield") }
        }
        .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    @Environment(VaultStore.self) private var store
    @AppStorage(Preferences.autoLockMinutes) private var autoLockMinutes = 5
    @AppStorage(Preferences.lockOnSleep) private var lockOnSleep = true
    @AppStorage(Preferences.clipboardClearSeconds) private var clipboardClearSeconds = 30
    @AppStorage(Preferences.appearance) private var appearance = "light"

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Match System").tag("system")
                }
            }

            Section {
                Picker("Lock after inactivity", selection: $autoLockMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Divider()
                    Text("Never").tag(0)
                }
                Toggle("Lock when Mac sleeps or screen locks", isOn: $lockOnSleep)
            }

            Section {
                Picker("Clear copied passwords after", selection: $clipboardClearSeconds) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Divider()
                    Text("Never").tag(0)
                }
            }

            ImportSection()

            Section {
                LabeledContent("Vault file") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.storage.url])
                    }
                    .disabled(!store.storage.exists)
                }
            } footer: {
                Text("The vault file is fully encrypted. Copy it somewhere safe to back it up.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Merges another vault file (an older vault.safespace, a backup, another Mac's vault) into this one.
private struct ImportSection: View {
    @Environment(VaultStore.self) private var store
    @State private var file: URL?
    @State private var password = ""
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        Section {
            if store.state == .unlocked {
                LabeledContent("Import logins") {
                    Button("Choose Vault File…", action: choose)
                        .disabled(store.isBusy)
                }
                if let file {
                    SecureField("Password for \(file.lastPathComponent)", text: $password)
                        .onSubmit(run)
                    HStack {
                        Spacer()
                        Button("Cancel") { reset() }
                        Button("Import", action: run)
                            .keyboardShortcut(.defaultAction)
                            .disabled(password.isEmpty || store.isBusy)
                    }
                }
                if let message {
                    Text(message.text)
                        .foregroundStyle(message.isError ? .red : .green)
                        .font(.callout)
                }
            } else {
                Text("Unlock your vault to import logins from another vault file.")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Adds the logins and groups from another Safespace vault: vault.dat (also from the original SafeSpace for Windows, whose categories become groups), or vault.safespace from an older version. Logins you already have are kept.")
                .foregroundStyle(.secondary)
        }
    }

    private func choose() {
        guard let url = VaultFilePicker.choose(prompt: "Choose") else { return }
        file = url
        password = ""
        message = nil
    }

    private func reset() {
        file = nil
        password = ""
    }

    private func run() {
        guard let file, !password.isEmpty, !store.isBusy else { return }
        message = nil
        Task {
            do {
                let summary = try await store.importVault(from: file, password: password)
                reset()
                message = (summary.message, false)
                store.showToast(summary.message)
            } catch VaultError.wrongPassword {
                password = ""
                message = ("Wrong password for that vault file.", true)
            } catch {
                message = (error.localizedDescription, true)
            }
        }
    }
}

private struct SecuritySettings: View {
    @Environment(VaultStore.self) private var store
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var message: (text: String, isError: Bool)?
    @State private var touchIDMessage: String?
    @State private var touchIDBusy = false

    private var canChange: Bool {
        !current.isEmpty && new.count >= 8 && new == confirmation && !store.isBusy
    }

    var body: some View {
        Form {
            Section {
                if store.state == .unlocked {
                    SecureField("Current password", text: $current)
                    SecureField("New password", text: $new)
                    SecureField("Confirm new password", text: $confirmation)
                    if !new.isEmpty {
                        LabeledContent("Strength") { StrengthBadge(password: new) }
                    }
                    HStack {
                        if let message {
                            Text(message.text)
                                .foregroundStyle(message.isError ? .red : .green)
                                .font(.callout)
                        } else if !confirmation.isEmpty && new != confirmation {
                            Text("Passwords don't match.").foregroundStyle(.secondary).font(.callout)
                        } else if !new.isEmpty && new.count < 8 {
                            Text("Use at least 8 characters.").foregroundStyle(.secondary).font(.callout)
                        }
                        Spacer()
                        Button("Change Password", action: change)
                            .disabled(!canChange)
                    }
                } else {
                    Text("Unlock your vault to change the master password.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Master Password")
            }

            Section {
                if let reason = BiometricUnlock.unavailableReason {
                    LabeledContent("Unlock with Touch ID") {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                } else if store.state == .unlocked || store.biometricEnabled {
                    Toggle(isOn: Binding(get: { store.biometricEnabled }, set: setTouchID)) {
                        Label("Unlock with Touch ID", systemImage: "touchid")
                    }
                    .disabled(touchIDBusy || (store.state != .unlocked && !store.biometricEnabled))
                    if let touchIDMessage {
                        Text(touchIDMessage).font(.callout).foregroundStyle(.red)
                    }
                } else {
                    Text("Unlock your vault to turn on Touch ID.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Touch ID")
            } footer: {
                Text("Your vault key is sealed inside this Mac's Secure Enclave and released only after a fingerprint match. Adding or removing fingerprints turns this off. Your master password always works too.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Encryption", value: "AES-256-GCM")
                LabeledContent("Key derivation", value: "PBKDF2-SHA256 · \(Vault.defaultIterations.formatted()) rounds")
                LabeledContent("Storage", value: "Local only")
            } header: {
                Text("About Your Vault")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setTouchID(_ enabled: Bool) {
        touchIDMessage = nil
        guard enabled else {
            store.disableBiometrics()
            return
        }
        touchIDBusy = true
        Task {
            defer { touchIDBusy = false }
            do {
                try await store.enableBiometrics()
            } catch BiometricError.cancelled {
                // Toggle stays off.
            } catch {
                touchIDMessage = error.localizedDescription
            }
        }
    }

    private func change() {
        message = nil
        Task {
            do {
                try await store.changePassword(current: current, new: new)
                current = ""
                new = ""
                confirmation = ""
                message = ("Master password changed.", false)
            } catch {
                message = (error.localizedDescription, true)
            }
        }
    }
}
