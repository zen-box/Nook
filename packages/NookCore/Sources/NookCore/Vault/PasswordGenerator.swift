import Foundation

/// Random passwords for new vault entries.
public enum PasswordGenerator {
    /// Letters without look-alikes (I, l, O).
    public static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    /// Digits without 0 and 1, which look like O and l.
    public static let digits = Array("23456789")
    /// Symbols that are easy to type on a phone keyboard.
    public static let symbols = Array("!@#$%&*-_+=?")

    /// Uses the system's secure random source.
    public static func make(length: Int = 20, includeSymbols: Bool = true) -> String {
        var generator = SystemRandomNumberGenerator()
        return make(length: length, includeSymbols: includeSymbols, using: &generator)
    }

    /// Always contains at least one letter and one digit, and one symbol when `includeSymbols`.
    public static func make<G: RandomNumberGenerator>(
        length: Int,
        includeSymbols: Bool,
        using generator: inout G
    ) -> String {
        precondition(length >= 4, "Passwords need at least 4 characters")
        var pools = [letters, digits]
        if includeSymbols {
            pools.append(symbols)
        }
        let all = pools.flatMap { $0 }
        var characters: [Character] = []
        for pool in pools {
            characters.append(pool[Int.random(in: 0..<pool.count, using: &generator)])
        }
        while characters.count < length {
            characters.append(all[Int.random(in: 0..<all.count, using: &generator)])
        }
        characters.shuffle(using: &generator)
        return String(characters)
    }
}
