import SafespaceCore
import SwiftUI

struct RootView: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        Group {
            switch store.state {
            case .setup: SetupView()
            case .locked: UnlockView()
            case .unlocked: VaultView()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: store.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Toast(message: toast)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .background(WindowChrome())
    }
}

/// One widget card centred on the canvas: form in the body, primary action as the footer.
private struct AuthLayout<Content: View, Footer: View>: View {
    let eyebrow: String
    let title: String
    let status: String
    let statusColor: Color
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            TopBar { EmptyView() }

            Spacer(minLength: 24)

            WidgetCard {
                WidgetHeader(eyebrow: eyebrow, title: title) {
                    StatusLabel(status, color: statusColor)
                }
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(17)
                footer
                WidgetFoot(text: "AES-256-GCM · PBKDF2 \(Vault.defaultIterations.formatted()) rounds · Local only")
            }
            .frame(width: 380)

            Spacer(minLength: 24)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct SetupView: View {
    private enum Field { case password, confirmation }

    @Environment(VaultStore.self) private var store
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var touchIDAvailable = BiometricUnlock.unavailableReason == nil
    @State private var useTouchID = true
    @FocusState private var focus: Field?

    private let minimumLength = 8

    private var validationMessage: String? {
        if password.count < minimumLength { return "Use at least \(minimumLength) characters" }
        if password != confirmation { return "Passwords don't match" }
        return nil
    }

    private var hint: String? {
        if password.isEmpty { return "There is no password recovery. Keep it somewhere safe." }
        if password.count < minimumLength { return "Use at least \(minimumLength) characters." }
        if !confirmation.isEmpty, password != confirmation { return "Passwords don't match." }
        return nil
    }

    var body: some View {
        AuthLayout(eyebrow: "New vault", title: "Create your vault", status: "No vault", statusColor: Theme.whisper) {
            Eyebrow("Master password").padding(.bottom, 7)
            SecureField("", text: $password, prompt: Text("At least \(minimumLength) characters").foregroundColor(Theme.whisper))
                .focused($focus, equals: .password)
                .onSubmit { focus = .confirmation }
                .inputField(focused: focus == .password)

            Eyebrow("Confirm").padding(.top, 14).padding(.bottom, 7)
            SecureField("", text: $confirmation, prompt: Text("Repeat password").foregroundColor(Theme.whisper))
                .focused($focus, equals: .confirmation)
                .onSubmit(create)
                .inputField(focused: focus == .confirmation)

            StrengthMeter(entropy: PasswordStrength.estimateEntropy(of: password), showBits: false)
                .opacity(password.isEmpty ? 0.4 : 1)
                .padding(.top, 18)

            Text(error ?? hint ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(error != nil ? Theme.red : Theme.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if touchIDAvailable {
                Toggle("Unlock with Touch ID", isOn: $useTouchID)
                    .toggleStyle(WidgetToggleStyle())
                    .padding(.top, 14)
            }
        } footer: {
            Button(store.isBusy ? "Creating vault" : "Create vault", action: create)
                .buttonStyle(CellButtonStyle(prominent: true, height: 44))
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil || store.isBusy)
                .overlay(alignment: .top) { Hairline() }
        }
        .onAppear { focus = .password }
    }

    private func create() {
        guard validationMessage == nil, !store.isBusy else { return }
        Task {
            do {
                try await store.createVault(password: password)
            } catch {
                self.error = error.localizedDescription
                return
            }
            guard useTouchID, touchIDAvailable else { return }
            do {
                try await store.enableBiometrics()
                store.showToast("Touch ID unlock is on")
            } catch BiometricError.cancelled {
                // They can turn it on later in Settings.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct UnlockView: View {
    @Environment(VaultStore.self) private var store
    @State private var password = ""
    @State private var error: String?
    @State private var attempts = 0
    @FocusState private var focused: Bool

    var body: some View {
        AuthLayout(eyebrow: "This Mac", title: "Vault locked", status: "Locked", statusColor: Theme.red) {
            Eyebrow("Master password").padding(.bottom, 7)
            SecureField("", text: $password, prompt: Text("Enter password").foregroundColor(Theme.whisper))
                .focused($focused)
                .onSubmit(unlock)
                .disabled(store.isBusy)
                .inputField(focused: focused)
                .shake(attempts)
                .animation(.linear(duration: 0.4), value: attempts)

            Text(error ?? (store.biometricEnabled ? "Touch ID is ready." : "Password only."))
                .font(.system(size: 11))
                .foregroundStyle(error != nil ? Theme.red : Theme.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        } footer: {
            HStack(spacing: 0) {
                if store.biometricEnabled {
                    Button(action: unlockWithTouchID) {
                        Label("Touch ID", systemImage: "touchid")
                    }
                    .buttonStyle(CellButtonStyle(height: 44))
                    .disabled(store.isBusy)
                    Hairline(vertical: true).frame(height: 44)
                }
                Button(store.isBusy ? "Unlocking" : "Unlock vault", action: unlock)
                    .buttonStyle(CellButtonStyle(prominent: true, height: 44))
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || store.isBusy)
            }
            .overlay(alignment: .top) { Hairline() }
        }
        .onAppear {
            focused = true
            autoPromptTouchID()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            autoPromptTouchID()
        }
    }

    /// Shows the fingerprint prompt once per lock, and only while Safespace is the frontmost app.
    private func autoPromptTouchID() {
        guard store.biometricEnabled, !store.suppressBiometricPrompt, NSApp.isActive else { return }
        store.suppressBiometricPrompt = true
        unlockWithTouchID()
    }

    private func unlockWithTouchID() {
        Task {
            do {
                try await store.unlockWithBiometrics()
            } catch BiometricError.cancelled {
                focused = true
            } catch {
                self.error = error.localizedDescription
                focused = true
            }
        }
    }

    private func unlock() {
        guard !password.isEmpty, !store.isBusy else { return }
        Task {
            do {
                try await store.unlock(password: password)
            } catch {
                self.error = error.localizedDescription
                attempts += 1
                password = ""
                focused = true
            }
        }
    }
}
