import Foundation

public struct PasswordOptions: Equatable, Sendable {
    public static let defaultSymbols = "!@#$%^&*()-_=+[]{};:,.<>?/~"

    public var length: Int
    public var uppercase: Bool
    public var lowercase: Bool
    public var digits: Bool
    public var symbols: Bool
    public var symbolSet: String
    public var excludeAmbiguous: Bool
    /// Guarantee at least one character from every enabled set.
    public var requireEveryType: Bool

    public init(
        length: Int = 20,
        uppercase: Bool = true,
        lowercase: Bool = true,
        digits: Bool = true,
        symbols: Bool = true,
        symbolSet: String = PasswordOptions.defaultSymbols,
        excludeAmbiguous: Bool = false,
        requireEveryType: Bool = true
    ) {
        self.length = length
        self.uppercase = uppercase
        self.lowercase = lowercase
        self.digits = digits
        self.symbols = symbols
        self.symbolSet = symbolSet
        self.excludeAmbiguous = excludeAmbiguous
        self.requireEveryType = requireEveryType
    }
}

public struct PassphraseOptions: Equatable, Sendable {
    public var wordCount: Int
    public var separator: String
    public var capitalize: Bool
    public var includeNumber: Bool

    public init(wordCount: Int = 5, separator: String = "-", capitalize: Bool = true, includeNumber: Bool = true) {
        self.wordCount = wordCount
        self.separator = separator
        self.capitalize = capitalize
        self.includeNumber = includeNumber
    }
}

/// All randomness comes from `SystemRandomNumberGenerator`, which on Apple platforms is a
/// cryptographically secure source (`arc4random_buf`). `randomElement(using:)` is unbiased.
public enum PasswordGenerator {
    static let ambiguous: Set<Character> = ["I", "l", "1", "O", "0", "o", "|", "`", "'", "\""]

    public static func characterSets(for options: PasswordOptions) -> [[Character]] {
        var sets: [[Character]] = []
        if options.uppercase { sets.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
        if options.lowercase { sets.append(Array("abcdefghijklmnopqrstuvwxyz")) }
        if options.digits { sets.append(Array("0123456789")) }
        if options.symbols {
            var seen = Set<Character>()
            let symbols = options.symbolSet.filter { ch in
                !ch.isLetter && !ch.isNumber && !ch.isWhitespace && seen.insert(ch).inserted
            }
            sets.append(Array(symbols))
        }
        if options.excludeAmbiguous {
            sets = sets.map { $0.filter { !ambiguous.contains($0) } }
        }
        return sets.filter { !$0.isEmpty }
    }

    public static func generate(_ options: PasswordOptions) -> String {
        var rng = SystemRandomNumberGenerator()
        let sets = characterSets(for: options)
        guard !sets.isEmpty, options.length > 0 else { return "" }
        let pool = sets.flatMap { $0 }

        var chars: [Character] = []
        chars.reserveCapacity(options.length)
        if options.requireEveryType && options.length >= sets.count {
            for set in sets {
                chars.append(set.randomElement(using: &rng)!)
            }
        }
        while chars.count < options.length {
            chars.append(pool.randomElement(using: &rng)!)
        }
        chars.shuffle(using: &rng)
        return String(chars)
    }

    public static func entropy(of options: PasswordOptions) -> Double {
        let poolSize = characterSets(for: options).reduce(0) { $0 + $1.count }
        guard poolSize > 1 else { return 0 }
        return Double(options.length) * log2(Double(poolSize))
    }

    public static func generate(_ options: PassphraseOptions) -> String {
        var rng = SystemRandomNumberGenerator()
        let count = max(1, options.wordCount)
        var words = (0..<count).map { _ in WordList.words.randomElement(using: &rng)! }
        if options.capitalize {
            words = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }
        if options.includeNumber {
            let index = Int.random(in: 0..<count, using: &rng)
            words[index] += String(Int.random(in: 0...9, using: &rng))
        }
        return words.joined(separator: options.separator)
    }

    public static func entropy(of options: PassphraseOptions) -> Double {
        let count = max(1, options.wordCount)
        var bits = Double(count) * log2(Double(WordList.words.count))
        if options.includeNumber {
            bits += log2(10) + log2(Double(count))
        }
        return bits
    }
}
