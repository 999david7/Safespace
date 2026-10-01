import AppKit
import SafespaceCore
import SwiftUI

extension EntryGroup {
    var tint: Color { Color(hex: color) }

    /// Readable text color for labels drawn on top of `tint`.
    var onTint: Color {
        let r = Double((color >> 16) & 0xFF), g = Double((color >> 8) & 0xFF), b = Double(color & 0xFF)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luminance > 0.62 ? Theme.onSignal : .white
    }

    var displayName: String { name.isEmpty ? "Untitled group" : name }
}

// MARK: - Chip

/// Square color swatch and tracked name; filled with the group's color when selected.
struct GroupChip: View {
    let group: EntryGroup
    var count: Int?
    var selected = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(selected ? group.onTint : group.tint)
                    .frame(width: 6, height: 6)
                Text(group.displayName)
                    .font(.mono(8.5, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.mono(8.5, weight: .regular))
                        .opacity(0.6)
                }
            }
            .foregroundStyle(selected ? group.onTint : Theme.ink)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(selected ? group.tint : (hovering ? group.tint.opacity(0.12) : Theme.paper), in: shape)
            .overlay(shape.strokeBorder(selected ? group.tint : Theme.lineStrong, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Non-interactive group marker for headers: swatch plus name in the group's color.
struct GroupTag: View {
    let group: EntryGroup

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(group.tint).frame(width: 6, height: 6)
            Eyebrow(group.displayName, color: group.tint, size: 8, tracking: 1.3)
        }
    }
}

// MARK: - Editor

/// Name and color for a new or existing group.
struct GroupEditorView: View {
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EntryGroup
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private let isNew: Bool
    private let onSave: (EntryGroup) -> Void

    init(group: EntryGroup, isNew: Bool, onSave: @escaping (EntryGroup) -> Void = { _ in }) {
        _draft = State(initialValue: group)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { draft.tint },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let channel = { (value: CGFloat) in UInt32((min(max(value, 0), 1) * 255).rounded()) }
                draft.color = channel(srgb.redComponent) << 16 | channel(srgb.greenComponent) << 8 | channel(srgb.blueComponent)
            }
        )
    }

    var body: some View {
        WidgetCard(plain: true) {
            WidgetHeader(eyebrow: isNew ? "New group" : "Edit group") {
                TextField("", text: $draft.name, prompt: Text("Group name").foregroundColor(Theme.whisper))
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(save)
            } trailing: {
                GroupChip(group: draft, selected: true) {}
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Color")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                    ForEach(EntryGroup.palette, id: \.self) { hex in
                        swatch(hex)
                    }
                    ColorPicker("", selection: customColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 26, height: 26)
                        .help("Custom color")
                }

                if let error {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(CellButtonStyle(height: 42))
                    .keyboardShortcut(.cancelAction)
                Hairline(vertical: true).frame(height: 42)
                Button(isNew ? "Add group" : "Save group", action: save)
                    .buttonStyle(CellButtonStyle(prominent: true, height: 42))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(width: 320)
        .onAppear { nameFocused = true }
    }

    private func swatch(_ hex: UInt32) -> some View {
        let selected = draft.color == hex
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return Button { draft.color = hex } label: {
            shape
                .fill(Color(hex: hex))
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EntryGroup(name: "", color: hex).onTint)
                    }
                }
                .overlay(shape.strokeBorder(selected ? Theme.ink : Theme.line, lineWidth: selected ? 1.5 : 1))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave else { return }
        do {
            try store.save(draft)
            onSave(draft)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
