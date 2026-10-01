import SafespaceCore
import SwiftUI

enum VaultFilter: Hashable, CaseIterable {
    case all, favorites, weak, reused

    var title: String {
        switch self {
        case .all: "All logins"
        case .favorites: "Favorites"
        case .weak: "Weak passwords"
        case .reused: "Reused passwords"
        }
    }

    var short: String {
        switch self {
        case .all: "All"
        case .favorites: "Fav"
        case .weak: "Weak"
        case .reused: "Reused"
        }
    }

    var tileLabel: String {
        switch self {
        case .all: "Logins"
        case .favorites: "Favorites"
        case .weak: "Weak"
        case .reused: "Reused"
        }
    }
}

/// The unlocked vault as a desk of widget cards: logins, the selected login, and health plus generator.
struct VaultView: View {
    @Environment(VaultStore.self) private var store
    @State private var filter: VaultFilter = .all
    @State private var search = ""
    @State private var selection: Entry.ID?
    @State private var editing: Entry?
    @State private var pendingDelete: Entry?
    @State private var errorMessage: String?
    @State private var showGenerator = false
    /// Narrows the list to one group, on top of `filter`.
    @State private var groupFilter: EntryGroup.ID?
    @State private var editingGroup: GroupDraft?
    @State private var pendingGroupDelete: EntryGroup?
    @FocusState private var searchFocused: Bool

    // MARK: - Derived data

    private var weakIDs: Set<UUID> {
        Set(store.entries.filter {
            !$0.password.isEmpty
                && PasswordStrength(entropy: PasswordStrength.estimateEntropy(of: $0.password)) <= .weak
        }.map(\.id))
    }

    private var reusedIDs: Set<UUID> {
        let groups = Dictionary(grouping: store.entries.filter { !$0.password.isEmpty }, by: \.password)
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }

    private func reuseCount(for entry: Entry) -> Int {
        guard !entry.password.isEmpty else { return 0 }
        return store.entries.filter { $0.id != entry.id && $0.password == entry.password }.count
    }

    private func count(for filter: VaultFilter) -> Int {
        switch filter {
        case .all: store.entries.count
        case .favorites: store.entries.filter(\.favorite).count
        case .weak: weakIDs.count
        case .reused: reusedIDs.count
        }
    }

    private var activeGroup: EntryGroup? {
        guard let groupFilter else { return nil }
        return store.groups.first { $0.id == groupFilter }
    }

    private func count(in group: EntryGroup) -> Int {
        store.entries.filter { $0.groupID == group.id }.count
    }

    private var filtered: [Entry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let weak = weakIDs
        let reused = reusedIDs
        let group = activeGroup?.id
        return store.entries
            .filter { group == nil || $0.groupID == group }
            .filter { entry in
                switch filter {
                case .all: return true
                case .favorites: return entry.favorite
                case .weak: return weak.contains(entry.id)
                case .reused: return reused.contains(entry.id)
                }
            }
            .filter { entry in
                query.isEmpty
                    || entry.title.localizedCaseInsensitiveContains(query)
                    || entry.username.localizedCaseInsensitiveContains(query)
                    || entry.url.localizedCaseInsensitiveContains(query)
                    || (store.group(for: entry)?.name.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var selectedEntry: Entry? {
        guard let selection else { return nil }
        return store.entries.first { $0.id == selection }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            TopBar {
                HStack(spacing: 8) {
                    StatusLabel("Unlocked", color: Theme.green)
                        .padding(.trailing, 8)
                    Button { showGenerator = true } label: { Image(systemName: "wand.and.stars") }
                        .buttonStyle(SquareButtonStyle(size: 28))
                        .help("Password Generator (⇧⌘G)")
                        .popover(isPresented: $showGenerator, arrowEdge: .bottom) {
                            GeneratorView(plain: true)
                                .frame(width: 360, height: 600)
                        }
                    Button(action: startNewEntry) { Image(systemName: "plus") }
                        .buttonStyle(SquareButtonStyle(size: 28))
                        .help("New Login (⌘N)")
                    Button { store.lock(manual: true) } label: { Image(systemName: "lock") }
                        .buttonStyle(SquareButtonStyle(size: 28))
                        .help("Lock Vault (⌘L)")
                }
            }

            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 14) {
                    listCard
                        .frame(width: 300)
                    panel
                        .frame(maxWidth: .infinity)
                    if geometry.size.width >= 1080 {
                        VStack(spacing: 14) {
                            healthCard
                            GeneratorView()
                        }
                        .frame(width: 320)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
        } message: { _ in
            Text("This can't be undone.")
        }
        .confirmationDialog(
            "Delete group “\(pendingGroupDelete?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingGroupDelete != nil }, set: { if !$0 { pendingGroupDelete = nil } }),
            presenting: pendingGroupDelete
        ) { group in
            Button("Delete Group", role: .destructive) { delete(group) }
        } message: { group in
            let count = count(in: group)
            Text(count == 0 ? "The group is empty." : "Its \(count) \(count == 1 ? "login stays" : "logins stay") in your vault, just ungrouped.")
        }
        .sheet(item: $editingGroup) { draft in
            GroupEditorView(group: draft.group, isNew: draft.isNew) { saved in
                if draft.isNew, let assign = draft.assign {
                    store.move(assign, to: saved)
                }
            }
        }
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if DEBUG
        .onAppear {
            guard let screen = store.demoScreen else { return }
            selection = store.entries.first { $0.title == "GitHub" }?.id
            if screen == "generator" { showGenerator = true }
            if screen == "editor" { editing = store.entries.first { $0.title == "GitHub" } }
            if screen == "stage" { selection = nil }
        }
        #endif
        .onChange(of: store.showGenerator) { _, requested in
            if requested {
                showGenerator = true
                store.showGenerator = false
            }
        }
        .onChange(of: store.newEntryRequested) { _, requested in
            if requested {
                startNewEntry()
                store.newEntryRequested = false
            }
        }
    }

    // MARK: - Logins card

    private var listCard: some View {
        let weak = weakIDs
        let reused = reusedIDs
        let entries = filtered

        return WidgetCard {
            WidgetHeader(eyebrow: activeGroup.map { "Group · \($0.displayName)" } ?? "Vault", title: filter.title) {
                Eyebrow("\(entries.count) \(entries.count == 1 ? "login" : "logins")", color: Theme.mute, tracking: 1.3)
            }

            searchField

            HStack(spacing: 0) {
                ForEach(Array(VaultFilter.allCases.enumerated()), id: \.element) { index, item in
                    if index > 0 { Hairline(vertical: true).frame(height: 34) }
                    Button("\(item.short) \(count(for: item))") { filter = item }
                        .buttonStyle(CellButtonStyle(selected: filter == item, height: 34))
                }
            }
            .overlay(alignment: .bottom) { Hairline() }

            groupStrip

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        EntryRow(
                            entry: entry,
                            group: store.group(for: entry),
                            isSelected: entry.id == selection && editing == nil,
                            flagged: weak.contains(entry.id) || reused.contains(entry.id)
                        ) {
                            select(entry)
                        }
                        .contextMenu { contextMenu(for: entry) }
                        Hairline()
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)
            .overlay {
                if entries.isEmpty {
                    Text(store.entries.isEmpty ? "No logins yet.\nPress ⌘N to add one." : "Nothing matches.")
                        .font(.condensed(16))
                        .foregroundStyle(Theme.whisper)
                        .multilineTextAlignment(.center)
                        .padding(30)
                }
            }

            Button(action: startNewEntry) {
                Label("New login", systemImage: "plus")
            }
            .buttonStyle(CellButtonStyle(height: 40))
            .overlay(alignment: .top) { Hairline() }
        }
        .onKeyPress(.upArrow) { moveSelection(-1, in: entries); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1, in: entries); return .handled }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.whisper)
            TextField("", text: $search, prompt: Text("Search logins").foregroundColor(Theme.whisper))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
            if search.isEmpty {
                Eyebrow("⌘F", tracking: 0)
            } else {
                Button { search = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.whisper)
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 40)
        .background(searchFocused ? Theme.paper : Theme.paperSoft)
        .overlay(alignment: .bottom) { Hairline() }
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
        )
    }

    /// Color-coded group chips. Tap to filter, tap again to clear; right-click to edit.
    private var groupStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if store.groups.isEmpty {
                        Eyebrow("No groups yet", tracking: 1.3)
                    }
                    ForEach(store.groups) { group in
                        GroupChip(group: group, count: count(in: group), selected: groupFilter == group.id) {
                            groupFilter = groupFilter == group.id ? nil : group.id
                        }
                        .contextMenu {
                            Button("Edit Group…") { editingGroup = GroupDraft(group: group, isNew: false) }
                            Button("Delete Group…", role: .destructive) { pendingGroupDelete = group }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.never)

            Button(action: startNewGroup) { Image(systemName: "plus") }
                .buttonStyle(SquareButtonStyle(size: 22))
                .help("New Group")
        }
        .padding(.horizontal, 17)
        .frame(height: 40)
        .background(Theme.paperSoft)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder
    private func contextMenu(for entry: Entry) -> some View {
        if !entry.username.isEmpty {
            Button("Copy Username") { store.copy(entry.username, label: "Username") }
        }
        if !entry.password.isEmpty {
            Button("Copy Password") { store.copy(entry.password, label: "Password") }
        }
        if let url = entry.websiteURL {
            Button("Open Website") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(entry.favorite ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(entry) }
        Menu("Move to Group") {
            ForEach(store.groups) { group in
                Toggle(group.displayName, isOn: Binding(
                    get: { entry.groupID == group.id },
                    set: { store.move(entry, to: $0 ? group : nil) }
                ))
            }
            if !store.groups.isEmpty { Divider() }
            Button("No Group") { store.move(entry, to: nil) }
                .disabled(entry.groupID == nil)
            Button("New Group…") { startNewGroup(assigning: entry) }
        }
        Button("Edit…") { editing = entry }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = entry }
    }

    // MARK: - Login card

    @ViewBuilder
    private var panel: some View {
        if let editing {
            EntryEditorView(
                entry: editing,
                isNew: !store.entries.contains { $0.id == editing.id },
                onSave: { saved in
                    self.editing = nil
                    selection = saved.id
                },
                onCancel: { self.editing = nil }
            )
            .id(editing.id)
        } else if let entry = selectedEntry {
            EntryDetailView(
                entry: entry,
                isWeak: weakIDs.contains(entry.id),
                reuseCount: reuseCount(for: entry),
                onEdit: { editing = entry },
                onDelete: { pendingDelete = entry },
                onClose: { selection = nil }
            )
            .id(entry.id)
        } else {
            WidgetCard {
                WidgetHeader(eyebrow: "Login", title: "Nothing selected")
                Text("Pick a login from the list,\nor add a new one.")
                    .font(.condensed(17))
                    .foregroundStyle(Theme.whisper)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Health card

    private var healthCard: some View {
        let weak = weakIDs.count
        let reused = reusedIDs.count
        let flagged = weakIDs.union(reusedIDs).count
        let total = store.entries.count
        let health = total == 0 ? 1 : 1 - Double(flagged) / Double(total)
        let tint = flagged == 0 ? Theme.green : (health >= 0.7 ? Theme.amber : Theme.red)

        return WidgetCard {
            WidgetHeader(eyebrow: "Security", title: "Vault health") {
                StatusLabel(flagged == 0 ? "Healthy" : "\(flagged) to fix", color: tint)
            }

            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    healthTile(.all, value: total)
                    healthTile(.favorites, value: count(for: .favorites))
                }
                HStack(spacing: 1) {
                    healthTile(.weak, value: weak, alert: weak > 0)
                    healthTile(.reused, value: reused, alert: reused > 0)
                }
            }
            .background(Theme.line)
            .overlay(alignment: .bottom) { Hairline() }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow("Score")
                    Spacer()
                    Eyebrow("\(Int((health * 100).rounded()))%", color: Theme.mute, tracking: 1)
                }
                LevelBar(fraction: health, tint: tint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Tapping a tile filters the list to it.
    private func healthTile(_ item: VaultFilter, value: Int, alert: Bool = false) -> some View {
        Button { filter = item } label: {
            StatTile(label: item.tileLabel, value: "\(value)", valueColor: alert ? Theme.red : Theme.ink)
                .overlay(alignment: .topTrailing) {
                    if filter == item {
                        Rectangle().fill(Theme.signal).frame(width: 6, height: 6).padding(12)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func select(_ entry: Entry) {
        editing = nil
        selection = entry.id
    }

    private func startNewEntry() {
        selection = nil
        // New logins land in the group being viewed.
        editing = Entry(groupID: groupFilter)
    }

    private func startNewGroup() {
        startNewGroup(assigning: nil)
    }

    private func startNewGroup(assigning entry: Entry?) {
        let group = EntryGroup(name: "", color: EntryGroup.suggestedColor(avoiding: store.groups))
        editingGroup = GroupDraft(group: group, isNew: true, assign: entry)
    }

    private func delete(_ group: EntryGroup) {
        do {
            try store.delete(group)
            if groupFilter == group.id { groupFilter = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveSelection(_ delta: Int, in entries: [Entry]) {
        guard editing == nil, !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : entries.count)
        let next = min(max(current + delta, 0), entries.count - 1)
        select(entries[next])
    }

    private func delete(_ entry: Entry) {
        do {
            try store.delete(entry)
            if selection == entry.id { selection = nil }
            if editing?.id == entry.id { editing = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A group open in the editor sheet, optionally with a login to file under it once created.
private struct GroupDraft: Identifiable {
    var group: EntryGroup
    var isNew: Bool
    var assign: Entry?
    var id: UUID { group.id }
}

private struct EntryRow: View {
    let entry: Entry
    let group: EntryGroup?
    let isSelected: Bool
    let flagged: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                EntryIcon(title: entry.title, size: 30, tint: group?.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title.isEmpty ? "Untitled" : entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.inkInverse : Theme.ink)
                        .lineLimit(1)
                    Text(entry.username.isEmpty ? (entry.host ?? "No username") : entry.username)
                        .font(.mono(9.5, weight: .regular))
                        .foregroundStyle(isSelected ? Theme.inkInverse.opacity(0.55) : Theme.mute)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                HStack(spacing: 5) {
                    if entry.favorite {
                        Rectangle().fill(Theme.signal).frame(width: 6, height: 6)
                    }
                    if flagged {
                        Circle().fill(Theme.red).frame(width: 6, height: 6)
                    }
                }
            }
            .padding(.horizontal, 17)
            .frame(height: 58)
            .background(isSelected ? Theme.ink : (hovering ? Theme.paperSoft : Theme.paper))
            .overlay(alignment: .leading) {
                if let group {
                    Rectangle().fill(group.tint).frame(width: 3)
                }
            }
            .help(group.map { "Group: \($0.displayName)" } ?? "")
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
