import SafespaceCore
import SwiftUI

enum GeneratorMode: String, CaseIterable {
    case password, passphrase
}

struct GeneratorView: View {
    @Environment(VaultStore.self) private var store

    /// Drops the card rim and shadow, for popovers.
    var plain = false
    /// When set, a "Use" button hands the result back (e.g. to the editor).
    var onUse: ((String) -> Void)?

    // Options are remembered between launches.
    @AppStorage("gen.mode") private var mode: GeneratorMode = .password
    @AppStorage("gen.length") private var length: Double = 20
    @AppStorage("gen.uppercase") private var uppercase = true
    @AppStorage("gen.lowercase") private var lowercase = true
    @AppStorage("gen.digits") private var digits = true
    @AppStorage("gen.symbols") private var symbols = true
    @AppStorage("gen.symbolSet") private var symbolSet = PasswordOptions.defaultSymbols
    @AppStorage("gen.excludeAmbiguous") private var excludeAmbiguous = false
    @AppStorage("gen.requireEveryType") private var requireEveryType = true
    @AppStorage("gen.words") private var wordCount: Double = 5
    @AppStorage("gen.separator") private var separator = "-"
    @AppStorage("gen.capitalize") private var capitalize = true
    @AppStorage("gen.includeNumber") private var includeNumber = true

    @State private var output = ""

    private var passwordOptions: PasswordOptions {
        PasswordOptions(
            length: Int(length.rounded()),
            uppercase: uppercase,
            lowercase: lowercase,
            digits: digits,
            symbols: symbols,
            symbolSet: symbolSet,
            excludeAmbiguous: excludeAmbiguous,
            requireEveryType: requireEveryType
        )
    }

    private var passphraseOptions: PassphraseOptions {
        PassphraseOptions(
            wordCount: Int(wordCount.rounded()),
            separator: separator,
            capitalize: capitalize,
            includeNumber: includeNumber
        )
    }

    private var entropy: Double {
        mode == .password
            ? PasswordGenerator.entropy(of: passwordOptions)
            : PasswordGenerator.entropy(of: passphraseOptions)
    }

    private var poolSize: Int {
        PasswordGenerator.characterSets(for: passwordOptions).reduce(0) { $0 + $1.count }
    }

    /// Changes whenever any option changes, to trigger regeneration.
    private var optionsKey: String {
        "\(mode)|\(passwordOptions)|\(passphraseOptions)"
    }

    var body: some View {
        WidgetCard(plain: plain) {
            WidgetHeader(eyebrow: "Generator", title: mode == .password ? "Password" : "Passphrase") {
                Eyebrow(
                    mode == .password ? "\(poolSize) chars" : "\(WordList.words.count) words",
                    color: Theme.mute,
                    tracking: 1.3
                )
            }

            HStack(spacing: 0) {
                Button("Password") { mode = .password }
                    .buttonStyle(CellButtonStyle(selected: mode == .password, height: 32))
                Hairline(vertical: true).frame(height: 32)
                Button("Passphrase") { mode = .passphrase }
                    .buttonStyle(CellButtonStyle(selected: mode == .passphrase, height: 32))
            }
            .overlay(alignment: .bottom) { Hairline() }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    ColoredPasswordText(value: output.isEmpty ? "—" : output)
                        .font(.mono(16, weight: .regular))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                    Button(action: regenerate) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(SquareButtonStyle(size: 28))
                        .help("Generate again")
                }
                StrengthMeter(entropy: entropy)
            }
            .padding(17)
            .overlay(alignment: .bottom) { Hairline() }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch mode {
                    case .password: passwordControls
                    case .passphrase: passphraseControls
                    }
                }
                .padding(17)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: .infinity)

            HStack(spacing: 0) {
                Button("Copy") {
                    store.copy(output, label: mode == .password ? "Password" : "Passphrase")
                }
                .buttonStyle(CellButtonStyle(prominent: onUse == nil, height: 40))
                .disabled(output.isEmpty)
                if let onUse {
                    Hairline(vertical: true).frame(height: 40)
                    Button("Use \(mode == .password ? "password" : "passphrase")") { onUse(output) }
                        .buttonStyle(CellButtonStyle(prominent: true, height: 40))
                        .disabled(output.isEmpty)
                }
            }
            .overlay(alignment: .top) { Hairline() }
        }
        .onAppear(perform: regenerate)
        .onChange(of: optionsKey) { regenerate() }
    }

    @ViewBuilder
    private var passwordControls: some View {
        ValueSlider(title: "Length", value: $length, range: 4...128)

        VStack(alignment: .leading, spacing: 7) {
            Eyebrow("Characters")
            CellToggles(items: [
                ("A–Z", $uppercase),
                ("a–z", $lowercase),
                ("0–9", $digits),
                ("#$&", $symbols),
            ])
        }

        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $excludeAmbiguous) { optionLabel("Avoid look-alikes", "Skips I, l, 1, O and 0") }
            Toggle(isOn: $requireEveryType) { optionLabel("Use every set", "At least one character from each") }
        }
        .toggleStyle(WidgetToggleStyle())

        if symbols {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Eyebrow("Symbol set")
                    Spacer()
                    if symbolSet != PasswordOptions.defaultSymbols {
                        Button("Reset") { symbolSet = PasswordOptions.defaultSymbols }
                            .buttonStyle(.plain)
                            .font(.mono(8, weight: .semibold))
                            .foregroundStyle(Theme.mute)
                    }
                }
                TextField("", text: $symbolSet)
                    .inputField(focused: false, monospaced: true, height: 34)
            }
        }
    }

    @ViewBuilder
    private var passphraseControls: some View {
        ValueSlider(title: "Words", value: $wordCount, range: 3...12)

        VStack(alignment: .leading, spacing: 7) {
            Eyebrow("Separator")
            HStack(spacing: 0) {
                ForEach(Array([("-", "-"), (".", "."), ("_", "_"), (" ", "␣"), ("", "None")].enumerated()), id: \.offset) { index, item in
                    if index > 0 { Hairline(vertical: true).frame(height: 32) }
                    Button(item.1) { separator = item.0 }
                        .buttonStyle(CellButtonStyle(selected: separator == item.0, height: 32))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.lineStrong))
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $capitalize) { optionLabel("Capitalize words", nil) }
            Toggle(isOn: $includeNumber) { optionLabel("Include a number", nil) }
        }
        .toggleStyle(WidgetToggleStyle())
    }

    private func optionLabel(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.mute)
            }
        }
    }

    private func regenerate() {
        output = mode == .password
            ? PasswordGenerator.generate(passwordOptions)
            : PasswordGenerator.generate(passphraseOptions)
    }
}

/// Caption, big condensed figure, and a slider.
private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline) {
                Eyebrow(title)
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(.condensed(28, .ultraLight))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            WidgetSlider(value: $value, range: range)
        }
    }
}

/// Multi-select row of cells; the last one switched on stays on.
private struct CellToggles: View {
    let items: [(title: String, isOn: Binding<Bool>)]

    var body: some View {
        let enabled = items.filter { $0.isOn.wrappedValue }.count
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Hairline(vertical: true).frame(height: 32) }
                Button(item.title) { item.isOn.wrappedValue.toggle() }
                    .buttonStyle(CellButtonStyle(selected: item.isOn.wrappedValue, uppercase: false, height: 32))
                    .disabled(item.isOn.wrappedValue && enabled == 1)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.lineStrong))
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}
