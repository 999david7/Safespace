import SafespaceCore
import SwiftUI

struct EntryDetailView: View {
    @Environment(VaultStore.self) private var store
    let entry: Entry
    let isWeak: Bool
    let reuseCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var revealed = false

    /// The UI is English, so format dates in English while keeping the user's region conventions.
    private static let appLocale = Locale(identifier: "en_\(Locale.current.region?.identifier ?? "US")")

    private var entropy: Double {
        PasswordStrength.estimateEntropy(of: entry.password)
    }

    private var warnings: [String] {
        var result: [String] = []
        if isWeak { result.append("This password is weak and easy to guess.") }
        if reuseCount > 0 {
            result.append("Also used by \(reuseCount) other \(reuseCount == 1 ? "login" : "logins"). One breach exposes them all.")
        }
        return result
    }

    var body: some View {
        WidgetCard {
            WidgetHeader(eyebrow: entry.host ?? "No website", title: entry.title.isEmpty ? "Untitled" : entry.title) {
                HStack(spacing: 6) {
                    if let group = store.group(for: entry) {
                        GroupTag(group: group)
                            .padding(.trailing, 6)
                    }
                    Button { store.toggleFavorite(entry) } label: {
                        Image(systemName: entry.favorite ? "star.fill" : "star")
                    }
                    .buttonStyle(SquareButtonStyle(size: 26))
                    .help(entry.favorite ? "Remove from Favorites" : "Add to Favorites")
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(SquareButtonStyle(size: 26))
                        .help("Close")
                }
            }

            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.red).frame(width: 6, height: 6)
                    Text(warning)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 10)
                .background(Theme.red.opacity(0.07))
                .overlay(alignment: .bottom) { Hairline() }
            }

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            usernameTile
                            websiteTile
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 1) {
                            passwordTile
                            strengthTile
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .background(Theme.line)
                    .overlay(alignment: .bottom) { Hairline() }

                    if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow("Notes")
                            Text(entry.notes)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(17)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)

            WidgetFoot(text: "Created \(entry.createdAt.formatted(.dateTime.day().month(.abbreviated).year().locale(Self.appLocale))) · Edited \(entry.updatedAt.formatted(.relative(presentation: .named).locale(Self.appLocale)))")

            HStack(spacing: 0) {
                if !entry.password.isEmpty {
                    Button("Copy password") { store.copy(entry.password, label: "Password") }
                        .buttonStyle(CellButtonStyle(prominent: true, height: 42))
                    Hairline(vertical: true).frame(height: 42)
                }
                Button("Edit", action: onEdit)
                    .buttonStyle(CellButtonStyle(height: 42))
                    .keyboardShortcut("e")
                Hairline(vertical: true).frame(height: 42)
                Button("Delete", action: onDelete)
                    .buttonStyle(CellButtonStyle(destructive: true, height: 42))
            }
            .overlay(alignment: .top) { Hairline() }
        }
    }

    // MARK: - Tiles

    private var usernameTile: some View {
        ValueTile(label: "Username") {
            Text(entry.username.isEmpty ? "—" : entry.username)
                .textSelection(.enabled)
        } actions: {
            if !entry.username.isEmpty {
                Button { store.copy(entry.username, label: "Username") } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(SquareButtonStyle(size: 26))
                    .help("Copy Username")
            }
        }
    }

    private var websiteTile: some View {
        ValueTile(label: "Website") {
            Text(entry.host ?? (entry.url.isEmpty ? "—" : entry.url))
                .textSelection(.enabled)
        } actions: {
            if let url = entry.websiteURL {
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(SquareButtonStyle(size: 26))
                    .help("Open Website")
            }
        }
    }

    private var passwordTile: some View {
        ValueTile(label: "Password") {
            Group {
                if entry.password.isEmpty {
                    Text("—")
                } else if revealed {
                    ColoredPasswordText(value: entry.password).textSelection(.enabled)
                } else {
                    Text(String(repeating: "•", count: 12)).foregroundStyle(Theme.mute)
                }
            }
            .font(.mono(13, weight: .regular))
        } actions: {
            if !entry.password.isEmpty {
                Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                    .buttonStyle(SquareButtonStyle(size: 26))
                    .help(revealed ? "Hide" : "Show")
                Button { store.copy(entry.password, label: "Password") } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(SquareButtonStyle(size: 26))
                    .help("Copy Password")
            }
        }
    }

    private var strengthTile: some View {
        let strength = PasswordStrength(entropy: entropy)
        return StatTile(
            label: "Strength",
            value: entry.password.isEmpty ? "—" : "\(Int(entropy.rounded()))",
            sub: entry.password.isEmpty ? "No password" : "bits · \(strength.label.lowercased())"
        ) {
            LevelBar(fraction: entry.password.isEmpty ? 0 : Double(strength.rawValue + 1) / 5, tint: strength.tint)
                .padding(.top, 4)
        }
    }
}

/// Caption, value and square actions, laid out like a widget tile.
private struct ValueTile<Value: View, Actions: View>: View {
    let label: String
    @ViewBuilder var value: Value
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(label)
            value
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 5) { actions }
                .frame(height: 26)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
    }
}
