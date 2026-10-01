import Foundation

public enum PasswordStrength: Int, Comparable, CaseIterable, Sendable {
    case veryWeak, weak, fair, strong, veryStrong

    public init(entropy: Double) {
        switch entropy {
        case ..<28: self = .veryWeak
        case ..<45: self = .weak
        case ..<60: self = .fair
        case ..<80: self = .strong
        default: self = .veryStrong
        }
    }

    public var label: String {
        switch self {
        case .veryWeak: "Very weak"
        case .weak: "Weak"
        case .fair: "Fair"
        case .strong: "Strong"
        case .veryStrong: "Very strong"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static let common: Set<String> = [
        "password", "123456", "12345678", "123456789", "qwerty", "abc123", "111111",
        "letmein", "welcome", "admin", "iloveyou", "monkey", "dragon", "passw0rd",
        "password1", "qwerty123", "1234567890", "football", "baseball", "sunshine",
    ]

    /// A rough entropy estimate for a password the user typed themselves.
    public static func estimateEntropy(of password: String) -> Double {
        guard !password.isEmpty else { return 0 }
        if common.contains(password.lowercased()) { return 0 }

        var pool = 0
        if password.contains(where: { $0.isLowercase }) { pool += 26 }
        if password.contains(where: { $0.isUppercase }) { pool += 26 }
        if password.contains(where: { $0.isNumber }) { pool += 10 }
        if password.contains(where: { $0.isASCII && !$0.isLetter && !$0.isNumber }) { pool += 33 }
        if password.contains(where: { !$0.isASCII }) { pool += 100 }
        guard pool > 1 else { return 0 }

        let length = Double(password.count)
        let uniqueRatio = Double(Set(password).count) / length
        // Penalise repetition like "aaaaaaaa" or "abababab".
        let repetitionFactor = min(1, uniqueRatio + 0.35)
        return length * log2(Double(pool)) * repetitionFactor
    }
}
