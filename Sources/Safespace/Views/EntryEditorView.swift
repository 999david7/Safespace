import SafespaceCore
import SwiftUI

struct EntryEditorView: View {
    private enum Field { case title, username, website, password }

    @Environment(VaultStore.self) private var store

    @State private var draft: Entry
    @State private var reveal = false
    @State private var showGenerator = false
    @State private var newGroup: EntryGroup?
    @State private var error: String?
    @FocusState private var focus: Field?

    private let original: Entry
    private let isNew: Bool
    private let onSave: (Entry) -> Void
    private let onCancel: () -> Void

    init(entry: Entry, isNew: Bool, onSave: @escaping (Entry) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: entry)
        original = entry
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var statusText: String {
        if isNew { return "Draft" }
        return draft == original ? "No changes" : "Unsaved"
    }

    var body: some View {
        WidgetCard {
            WidgetHeader(eyebrow: isNew ? "New login" : "Editing") {
                TextField("", text: $draft.title, prompt: Text("Untitled").foregroundColor(Theme.whisper))
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .title)
            } trailing: {
                StatusLabel(statusText, color: draft == original && !isNew ? Theme.whisper : Theme.amber)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    field("Username") {
                        TextField("", text: $draft.username, prompt: Text("name@example.com").foregroundColor(Theme.whisper))
                            .textContentType(.username)
                            .focused($focus, equals: .username)
                            .inputField(focused: focus == .username)
                    }

                    field("Website") {
                        TextField("", text: $draft.url, prompt: Text("example.com").foregroundColor(Theme.whisper))
                            .focused($focus, equals: .website)
                            .inputField(focused: focus == .website)
                    }

                    field("Group") {
                        groupPicker
                    }

                    field("Password") {
                        HStack(spacing: 6) {
                            Group {
                                if reveal {
                                    TextField("", text: $draft.password, prompt: Text("Required").foregroundColor(Theme.whisper))
                                } else {
                                    SecureField("", text: $draft.password, prompt: Text("Required").foregroundColor(Theme.whisper))
                                }
                            }
                            .focused($focus, equals: .password)
                            .inputField(focused: focus == .password, monospaced: true)

                            Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                                .buttonStyle(SquareButtonStyle(size: 38))
                                .help(reveal ? "Hide" : "Show")

                            Button { showGenerator = true } label: { Image(systemName: "wand.and.stars") }
                                .buttonStyle(SquareButtonStyle(size: 38))
                                .help("Generate a password")
                                .popover(isPresented: $showGenerator, arrowEdge: .trailing) {
                                    GeneratorView(plain: true, onUse: { generated in
                                        draft.password = generated
                                        reveal = true
                                        showGenerator = false
                                    })
                                    .frame(width: 360, height: 600)
                                }
                        }
                    }

                    StrengthMeter(entropy: PasswordStrength.estimateEntropy(of: draft.password))
                        .opacity(draft.password.isEmpty ? 0.4 : 1)
                        .padding(.top, 16)

                    field("Notes") {
                        TextEditor(text: $draft.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 90)
                            .background(Theme.paperSoft, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.line))
                    }

                    Toggle("Pin to favorites", isOn: $draft.favorite)
                        .toggleStyle(WidgetToggleStyle())
                        .padding(.top, 18)

                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.red)
                            .padding(.top, 12)
                    }
                }
                .padding(17)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)

            HStack(spacing: 0) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(CellButtonStyle(height: 42))
                    .keyboardShortcut(.cancelAction)
                Hairline(vertical: true).frame(height: 42)
                Button(isNew ? "Add login" : "Save changes", action: save)
                    .buttonStyle(CellButtonStyle(prominent: true, height: 42))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .overlay(alignment: .top) { Hairline() }
        }
        .onAppear { if isNew { focus = .title } }
        .sheet(item: $newGroup) { group in
            GroupEditorView(group: group, isNew: true) { saved in
                draft.groupID = saved.id
            }
        }
    }

    private var selectedGroup: EntryGroup? {
        store.groups.first { $0.id == draft.groupID }
    }

    private var groupPicker: some View {
        Menu {
            Button("No Group") { draft.groupID = nil }
            if !store.groups.isEmpty { Divider() }
            ForEach(store.groups) { group in
                Button(group.displayName) { draft.groupID = group.id }
            }
            Divider()
            Button("New Group…") {
                newGroup = EntryGroup(name: "", color: EntryGroup.suggestedColor(avoiding: store.groups))
            }
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(selectedGroup?.tint ?? Theme.whisper.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(selectedGroup?.displayName ?? "No group")
                    .font(.system(size: 13))
                    .foregroundStyle(selectedGroup == nil ? Theme.whisper : Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.mute)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Theme.paperSoft, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(label)
            content()
        }
        .padding(.top, label == "Username" ? 0 : 16)
    }

    private func save() {
        guard canSave else { return }
        var entry = draft
        entry.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.username = entry.username.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.url = entry.url.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.save(entry)
            onSave(entry)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
