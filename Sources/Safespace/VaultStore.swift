import AppKit
import Observation
import SafespaceCore

@MainActor
@Observable
final class VaultStore {
    enum State {
        case setup, locked, unlocked
    }

    private(set) var state: State
    private(set) var entries: [Entry] = []
    private(set) var groups: [EntryGroup] = []
    private(set) var isBusy = false
    private(set) var toast: String?

    // UI requests that can come from menu commands.
    var newEntryRequested = false
    var showGenerator = false

    private(set) var biometricEnabled: Bool
    /// Set after a manual lock or once the automatic Touch ID prompt has been shown.
    @ObservationIgnored var suppressBiometricPrompt = false

    let storage: VaultStorage
    let biometrics: BiometricUnlock
    @ObservationIgnored private var unlocked: UnlockedVault?
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [Any] = []

    init(storage: VaultStorage = .default) {
        Preferences.register()
        self.storage = storage
        biometrics = BiometricUnlock(storage: storage)
        state = storage.exists ? .locked : .setup
        biometricEnabled = storage.exists && biometrics.isEnrolled
        startAutoLockMonitoring()
    }

    // MARK: - Lifecycle

    func createVault(password: String) async throws {
        isBusy = true
        defer { isBusy = false }
        let vault = try await Task.detached(priority: .userInitiated) {
            try Vault.create(password: password)
        }.value
        try storage.write(Vault.encrypt([], with: vault))
        open(vault, contents: VaultContents())
    }

    func unlock(password: String) async throws {
        isBusy = true
        defer { isBusy = false }
        let file = try storage.read()
        let (vault, contents) = try await Task.detached(priority: .userInitiated) {
            try Vault.decryptContents(file, password: password)
        }.value
        open(vault, contents: contents)
    }

    func unlockWithBiometrics() async throws {
        guard biometricEnabled, !isBusy else { return }
        let file = try storage.read()
        do {
            let key = try await biometrics.unlock(salt: file.salt)
            let (vault, contents) = try Vault.decryptContents(file, key: key)
            open(vault, contents: contents)
        } catch BiometricError.invalidated, VaultError.wrongPassword {
            disableBiometrics()
            throw BiometricError.invalidated
        }
    }

    func enableBiometrics() async throws {
        guard let unlocked else { return }
        if let reason = BiometricUnlock.unavailableReason {
            throw BiometricError.unavailable(reason)
        }
        try await BiometricUnlock.confirm(reason: "turn on Touch ID unlock for Safespace")
        try biometrics.enroll(vaultKey: unlocked.key, salt: unlocked.salt)
        biometricEnabled = true
    }

    func disableBiometrics() {
        biometrics.remove()
        biometricEnabled = false
    }

    /// - Parameter manual: the user locked on purpose, so don't immediately prompt for Touch ID.
    func lock(manual: Bool = false) {
        guard state == .unlocked else { return }
        suppressBiometricPrompt = manual
        unlocked = nil
        entries = []
        groups = []
        newEntryRequested = false
        showGenerator = false
        Clipboard.clearIfOwned()
        state = .locked
    }

    func changePassword(current: String, new: String) async throws {
        guard state == .unlocked else { return }
        isBusy = true
        defer { isBusy = false }
        let file = try storage.read()
        let snapshot = entries
        let groupSnapshot = groups
        let newVault = try await Task.detached(priority: .userInitiated) {
            _ = try Vault.decrypt(file, password: current)
            return try Vault.create(password: new)
        }.value
        try storage.write(Vault.encrypt(snapshot, groups: groupSnapshot, with: newVault))
        unlocked = newVault

        // The old Touch ID enrollment sealed the old key; re-seal the new one (no prompt needed).
        if biometricEnabled {
            do {
                try biometrics.enroll(vaultKey: newVault.key, salt: newVault.salt)
            } catch {
                disableBiometrics()
            }
        }
    }

    private func open(_ vault: UnlockedVault, contents: VaultContents) {
        unlocked = vault
        entries = contents.entries
        groups = contents.groups
        lastActivity = Date()
        state = .unlocked
    }

    // MARK: - Entries

    func save(_ entry: Entry) throws {
        var updated = entries
        var entry = entry
        entry.updatedAt = Date()
        if let index = updated.firstIndex(where: { $0.id == entry.id }) {
            updated[index] = entry
        } else {
            updated.append(entry)
        }
        try persist(updated)
    }

    func delete(_ entry: Entry) throws {
        try persist(entries.filter { $0.id != entry.id })
    }

    func toggleFavorite(_ entry: Entry) {
        var entry = entry
        entry.favorite.toggle()
        try? persist(entries.map { $0.id == entry.id ? entry : $0 })
    }

    /// Files `entry` under `group`, or takes it out of any group when `group` is nil.
    func move(_ entry: Entry, to group: EntryGroup?) {
        var entry = entry
        entry.groupID = group?.id
        try? persist(entries.map { $0.id == entry.id ? entry : $0 })
    }

    // MARK: - Groups

    func group(for entry: Entry) -> EntryGroup? {
        guard let id = entry.groupID else { return nil }
        return groups.first { $0.id == id }
    }

    /// Adds a new group or updates an existing one with the same id.
    func save(_ group: EntryGroup) throws {
        var group = group
        group.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = groups
        if let index = updated.firstIndex(where: { $0.id == group.id }) {
            updated[index] = group
        } else {
            updated.append(group)
        }
        try persist(entries, groups: updated)
    }

    /// Removes the group. Its logins are kept and simply become ungrouped.
    func delete(_ group: EntryGroup) throws {
        let ungrouped = entries.map { entry in
            var entry = entry
            if entry.groupID == group.id { entry.groupID = nil }
            return entry
        }
        try persist(ungrouped, groups: groups.filter { $0.id != group.id })
    }

    /// Writes to disk first and only then updates memory, so the UI never shows unsaved data.
    private func persist(_ newEntries: [Entry], groups newGroups: [EntryGroup]? = nil) throws {
        guard let unlocked else { return }
        let newGroups = newGroups ?? groups
        try storage.write(Vault.encrypt(newEntries, groups: newGroups, with: unlocked))
        entries = newEntries
        groups = newGroups
    }

    // MARK: - Clipboard & toast

    func copy(_ value: String, label: String) {
        let seconds = UserDefaults.standard.integer(forKey: Preferences.clipboardClearSeconds)
        Clipboard.copy(value, clearAfter: seconds)
        showToast(seconds > 0 ? "\(label) copied · clears in \(seconds)s" : "\(label) copied")
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Auto-lock

    private func startAutoLockMonitoring() {
        let activity = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.lastActivity = Date() }
            return event
        }
        if let activity { observers.append(activity) }

        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockIfIdle() }
        }
        observers.append(timer)

        let lockOnSystemEvent: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                if UserDefaults.standard.bool(forKey: Preferences.lockOnSleep) {
                    self?.lock()
                }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: lockOnSystemEvent))
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: lockOnSystemEvent))
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: lockOnSystemEvent
        ))
    }

    #if DEBUG
    /// Which screen a `SAFESPACE_DEMO` launch should show.
    @ObservationIgnored var demoScreen: String?

    /// Preview mode with sample data in a temporary vault. Launch with
    /// `SAFESPACE_DEMO=vault|generator|editor|locked|setup`. Never touches the real vault.
    static func demo(screen: String) -> VaultStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("safespace-demo-\(UUID().uuidString)")
        let storage = VaultStorage(url: directory.appendingPathComponent("vault.safespace"))
        let vault = try! Vault.create(password: "demo", iterations: 1_000)
        if screen != "setup" {
            try! storage.write(Vault.encrypt(sampleEntries, groups: sampleGroups, with: vault))
        }
        let store = VaultStore(storage: storage)
        store.demoScreen = screen
        if !["setup", "locked"].contains(screen) {
            let (unlocked, contents) = try! Vault.decryptContents(storage.read(), password: "demo")
            store.open(unlocked, contents: contents)
        }
        return store
    }

    private static let workGroup = EntryGroup(name: "Work", color: 0x3B7DD8)
    private static let financeGroup = EntryGroup(name: "Finance", color: 0x0B8F57)
    private static let streamingGroup = EntryGroup(name: "Streaming", color: 0xE06C9F)
    private static let sampleGroups = [workGroup, financeGroup, streamingGroup]

    private static let sampleEntries: [Entry] = [
        Entry(title: "GitHub", username: "jane.doe@example.com", password: "tmfEzEgKeHwpBD9BUJff", url: "github.com", notes: "Recovery codes are in the safe.", favorite: true, groupID: workGroup.id),
        Entry(title: "Google", username: "jane.doe@example.org", password: "Velvet-Comet-Ladder4-Prism", url: "accounts.google.com", favorite: true),
        Entry(title: "Apple ID", username: "jane@example.net", password: "9XvjsN8T3w", url: "appleid.apple.com"),
        Entry(title: "Netflix", username: "jane.doe@example.com", password: "password1", url: "netflix.com", groupID: streamingGroup.id),
        Entry(title: "Figma", username: "jdoe", password: "vCSwwq!7U0aI", url: "figma.com", groupID: workGroup.id),
        Entry(title: "Amazon Web Services", username: "demo-admin", password: "8%ETUM3REV8zJmO5x1nN", url: "console.aws.amazon.com", favorite: true, groupID: workGroup.id),
        Entry(title: "Spotify", username: "janedoe", password: "summer2024", url: "spotify.com", groupID: streamingGroup.id),
        Entry(title: "Notion", username: "jane.doe@example.com", password: "Harbor.Tulip.Engine.8", url: "notion.so", groupID: workGroup.id),
        Entry(title: "Chase Bank", username: "jdoe-demo", password: "!EN&yx0!TN#5", url: "chase.com", groupID: financeGroup.id),
    ]
    #endif

    private func lockIfIdle() {
        let minutes = UserDefaults.standard.integer(forKey: Preferences.autoLockMinutes)
        guard state == .unlocked, minutes > 0 else { return }
        if Date().timeIntervalSince(lastActivity) >= Double(minutes * 60) {
            lock()
        }
    }
}
