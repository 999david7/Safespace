import AppKit
import SafespaceCore
import SwiftUI

// MARK: - Tokens

/// V3ERA widget palette: paper cards on a quiet canvas, ink text, hairlines, and a yellow signal.
enum Theme {
    static let canvas = adaptive(light: 0xE9E8E4, dark: 0x050506)
    static let paper = adaptive(light: 0xFEFEFE, dark: 0x141415)
    static let paperSoft = adaptive(light: 0xF6F6F3, dark: 0x1C1C1E)
    static let ink = adaptive(light: 0x0A0A0B, dark: 0xF4F4F1)
    static let inkInverse = adaptive(light: 0xFFFFFF, dark: 0x0A0A0B)
    static let mute = ink.opacity(0.48)
    static let whisper = ink.opacity(0.28)
    static let line = ink.opacity(0.11)
    static let lineStrong = ink.opacity(0.23)

    static let signal = Color(hex: 0xF2C500)
    /// Text drawn on the yellow signal, which stays dark in both appearances.
    static let onSignal = Color(hex: 0x0A0A0B)
    static let green = Color(hex: 0x0B8F57)
    static let amber = Color(hex: 0xE0A800)
    static let amberText = adaptive(light: 0xB07F00, dark: 0xF2C500)
    static let red = Color(hex: 0xD94B3D)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

extension Font {
    enum CondensedWeight: String {
        case ultraLight = "UltraLight", regular = "Regular", medium = "Medium", demiBold = "DemiBold"
    }

    /// Avenir Next Condensed, used for widget titles and big figures.
    static func condensed(_ size: CGFloat, _ weight: CondensedWeight = .regular) -> Font {
        .custom("AvenirNextCondensed-\(weight.rawValue)", fixedSize: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension PasswordStrength {
    var tint: Color {
        switch self {
        case .veryWeak, .weak: Theme.red
        case .fair: Theme.amber
        case .strong, .veryStrong: Theme.green
        }
    }
}

// MARK: - Primitives

/// Small tracked monospace caption, the label above every widget value.
struct Eyebrow: View {
    let text: String
    var color: Color
    var size: CGFloat
    var tracking: CGFloat

    init(_ text: String, color: Color = Theme.whisper, size: CGFloat = 8, tracking: CGFloat = 1.8) {
        self.text = text
        self.color = color
        self.size = size
        self.tracking = tracking
    }

    var body: some View {
        Text(text.uppercased())
            .font(.mono(size, weight: .semibold))
            .tracking(tracking)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct Hairline: View {
    var vertical = false
    var color: Color = Theme.line

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

struct StatusLabel: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Eyebrow(text, color: color, size: 8, tracking: 1.3)
        }
    }
}

// MARK: - Widget chrome

/// Paper card with a hairline rim and a soft drop shadow.
struct WidgetCard<Content: View>: View {
    /// Skips the rim and shadow, for cards shown inside a popover.
    var plain = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: plain ? 0 : 7, style: .continuous)
        VStack(spacing: 0) { content }
            .background(Theme.paper)
            .clipShape(shape)
            .overlay { if !plain { shape.strokeBorder(Theme.lineStrong, lineWidth: 1) } }
            .shadow(color: .black.opacity(plain ? 0 : 0.1), radius: 26, y: 14)
    }
}

/// Eyebrow and condensed title on the left, status on the right, hairline underneath.
struct WidgetHeader<Title: View, Trailing: View>: View {
    let eyebrow: String
    @ViewBuilder var title: Title
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(eyebrow, size: 7.5, tracking: 2.1)
                title
                    .font(.condensed(21))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

extension WidgetHeader where Title == Text {
    init(eyebrow: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.eyebrow = eyebrow
        self.title = Text(title)
        self.trailing = trailing()
    }
}

extension WidgetHeader where Title == Text, Trailing == EmptyView {
    init(eyebrow: String, title: String) {
        self.init(eyebrow: eyebrow, title: title) { EmptyView() }
    }
}

/// Muted monospace line at the bottom of a card.
struct WidgetFoot: View {
    let text: String

    var body: some View {
        HStack {
            Eyebrow(text, size: 7.5, tracking: 1.3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// A figure tile: caption, big condensed number, optional sub line.
struct StatTile<Accessory: View>: View {
    let label: String
    let value: String
    var sub: String?
    var valueColor: Color = Theme.ink
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(label)
            Text(value)
                .font(.condensed(32, .ultraLight))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let sub {
                Text(sub)
                    .font(.mono(8.5))
                    .foregroundStyle(Theme.mute)
                    .lineLimit(1)
            }
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.paper)
    }
}

extension StatTile where Accessory == EmptyView {
    init(label: String, value: String, sub: String? = nil, valueColor: Color = Theme.ink) {
        self.init(label: label, value: value, sub: sub, valueColor: valueColor) { EmptyView() }
    }
}

/// Top strip level with the traffic lights: wordmark on the left, controls on the right.
/// Place it in a stack that ignores the top safe area so it sits inside the title bar.
struct TopBar<Trailing: View>: View {
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.ink)
                    .frame(width: 14, height: 14)
                    .overlay(Rectangle().fill(Theme.signal).frame(width: 4, height: 4))
                Text("SAFESPACE")
                    .font(.mono(9.5, weight: .semibold))
                    .tracking(3.6)
                    .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 84)
            Spacer(minLength: 16)
            trailing.padding(.trailing, 16)
        }
        .frame(height: 28)
        .padding(.bottom, 12)
    }
}

// MARK: - Buttons

/// 2pt-radius square button with a hairline rim that turns signal yellow on hover.
struct SquareButtonStyle: ButtonStyle {
    var size: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        SquareButtonBody(configuration: configuration, size: size)
    }
}

private struct SquareButtonBody: View {
    let configuration: SquareButtonStyle.Configuration
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let active = hovering && isEnabled
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(active ? Theme.onSignal : Theme.ink)
            .frame(width: size, height: size)
            .background(active ? Theme.signal : Theme.paper, in: shape)
            .overlay(shape.strokeBorder(active ? Theme.onSignal : Theme.lineStrong, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}

/// Full-width cell with a tracked monospace label, as in the widgets' preset rows and footers.
/// Selected and prominent cells are solid ink; the rest invert on hover.
struct CellButtonStyle: ButtonStyle {
    var selected = false
    var prominent = false
    var destructive = false
    var uppercase = true
    var height: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        CellButtonBody(configuration: configuration, style: self)
    }
}

private struct CellButtonBody: View {
    let configuration: CellButtonStyle.Configuration
    let style: CellButtonStyle
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let (fill, text) = isEnabled ? colors(hovering: hovering) : (Theme.paperSoft, Theme.whisper)
        configuration.label
            .font(.mono(8.5, weight: .semibold))
            .tracking(1.3)
            .textCase(style.uppercase ? .uppercase : nil)
            .lineLimit(1)
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .frame(height: style.height)
            .background(fill)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func colors(hovering: Bool) -> (fill: Color, text: Color) {
        if style.prominent { return hovering ? (Theme.signal, Theme.onSignal) : (Theme.ink, Theme.inkInverse) }
        if style.selected { return (Theme.ink, Theme.inkInverse) }
        if style.destructive { return hovering ? (Theme.red, .white) : (Theme.paper, Theme.red) }
        return hovering ? (Theme.ink, Theme.inkInverse) : (Theme.paper, Theme.ink)
    }
}

// MARK: - Inputs

/// Soft-paper field that brightens with an ink rim when focused.
struct InputField: ViewModifier {
    var focused: Bool
    var monospaced = false
    var height: CGFloat = 38

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(monospaced ? .mono(13, weight: .regular) : .system(size: 13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(focused ? Theme.paper : Theme.paperSoft, in: shape)
            .overlay(shape.strokeBorder(focused ? Theme.ink : Theme.line, lineWidth: 1))
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

extension View {
    func inputField(focused: Bool, monospaced: Bool = false, height: CGFloat = 38) -> some View {
        modifier(InputField(focused: focused, monospaced: monospaced, height: height))
    }

    /// Horizontal shake used for a wrong password.
    func shake(_ trigger: Int) -> some View {
        modifier(ShakeEffect(animatableData: CGFloat(trigger)))
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Square ink checkbox with a label and optional hint.
struct WidgetToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                ZStack {
                    shape.fill(configuration.isOn ? Theme.ink : Theme.paper)
                    shape.strokeBorder(configuration.isOn ? Theme.ink : Theme.lineStrong, lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.inkInverse)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, 1)

                configuration.label
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 6pt rounded track with an ink fill and a ringed knob.
struct WidgetSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = CGFloat((value - range.lowerBound) / span)
            let x = geometry.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 6)
                Capsule().fill(Theme.ink).frame(width: max(x, 6), height: 6)
                Circle()
                    .fill(Theme.paper)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                    .frame(width: 15, height: 15)
                    .offset(x: x - 7.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = min(max(0, drag.location.x / geometry.size.width), 1)
                    value = (range.lowerBound + Double(position) * span).rounded()
                }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Meters

/// 6pt rounded bar, like the system widget's memory and disk bars.
struct LevelBar: View {
    let fraction: Double
    var tint: Color = Theme.ink

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.5), value: fraction)
    }
}

struct StrengthMeter: View {
    let entropy: Double
    var showBits = true

    var body: some View {
        let strength = PasswordStrength(entropy: entropy)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Eyebrow("Strength")
                Spacer()
                if showBits {
                    Eyebrow("\(Int(entropy.rounded())) bits", color: Theme.mute, tracking: 1)
                }
                StatusLabel(strength.label, color: strength.tint)
            }
            LevelBar(fraction: Double(strength.rawValue + 1) / 5, tint: strength.tint)
        }
    }
}

/// Compact strength indicator (used in Settings).
struct StrengthBadge: View {
    let strength: PasswordStrength

    init(password: String) {
        strength = PasswordStrength(entropy: PasswordStrength.estimateEntropy(of: password))
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(strength.tint).frame(width: 8, height: 8)
            Text(strength.label)
        }
    }
}

// MARK: - Entries

/// Soft square monogram for a login, washed in its group's color when it has one.
struct EntryIcon: View {
    let title: String
    var size: CGFloat = 30
    var tint: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        shape
            .fill(tint.map { $0.opacity(0.16) } ?? Theme.paperSoft)
            .background(Theme.paper, in: shape)
            .overlay(shape.strokeBorder(tint.map { $0.opacity(0.55) } ?? Theme.line, lineWidth: 1))
            .overlay {
                Text(title.first.map { String($0).uppercased() } ?? "?")
                    .font(.condensed(size * 0.56, .medium))
                    .foregroundStyle(tint ?? Theme.ink)
            }
            .frame(width: size, height: size)
    }
}

/// Password with digits and symbols tinted so characters are easy to read out. Set the font from outside.
struct ColoredPasswordText: View {
    let value: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for character in value {
            var piece = AttributedString(String(character))
            if character.isNumber {
                piece.foregroundColor = Theme.red
            } else if !character.isLetter {
                piece.foregroundColor = Theme.amberText
            }
            result += piece
        }
        return result
    }
}

// MARK: - Feedback

struct Toast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.signal).frame(width: 6, height: 6)
            Eyebrow(message, color: .white, size: 8.5, tracking: 1.3)
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color(hex: 0x0A0A0B), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}

// MARK: - Window

/// Transparent title bar so the top strip sits level with the traffic lights.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
    }
}
