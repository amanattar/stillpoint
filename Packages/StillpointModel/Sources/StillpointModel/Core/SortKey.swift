/// Fractional ordering keys.
///
/// A key is a base-62 fraction (`"V"` ≈ 0.5). A new key can always be made
/// between two others, so moving an item rewrites only that item's key.
/// Keys never end in `"0"`, which guarantees there is always room before them.
public enum SortKey {
    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// A key strictly between `lower` and `upper`. `nil` means unbounded.
    public static func between(_ lower: String?, _ upper: String?) -> String {
        let a = lower.map(Array.init) ?? []
        let b = upper.map(Array.init)
        if let b {
            precondition(a.lexicographicallyPrecedes(b), "SortKey.between: \(lower ?? "nil") must be < \(upper ?? "nil")")
        }
        // Appending and prepending are the common cases: step by one digit
        // instead of halving the gap, so keys grow ~1 char per 30-60 items.
        if lower != nil, b == nil {
            return String(increment(a))
        }
        if lower == nil, let b {
            return String(decrement(b))
        }
        return String(midpoint(a, b))
    }

    /// `count` ascending keys, all strictly between `lower` and `upper`.
    public static func sequence(count: Int, after lower: String?, before upper: String?) -> [String] {
        var keys: [String] = []
        var previous = lower
        for _ in 0..<count {
            let key = between(previous, upper)
            keys.append(key)
            previous = key
        }
        return keys
    }

    private static func index(_ c: Character) -> Int {
        digits.firstIndex(of: c)!
    }

    /// The shortest key greater than `a`.
    private static func increment(_ a: [Character]) -> [Character] {
        guard let first = a.first else { return [digits[digits.count / 2]] }
        let d = index(first)
        if d < digits.count - 1 {
            return [digits[d + 1]]
        }
        return [first] + increment(Array(a.dropFirst()))
    }

    /// A short key less than `b`, never ending in "0".
    private static func decrement(_ b: [Character]) -> [Character] {
        let d = index(b[0])
        if d >= 2 {
            return [digits[d - 1]]
        }
        if d == 1 {
            return ["0", digits[digits.count - 1]]
        }
        return ["0"] + decrement(Array(b.dropFirst()))
    }

    private static func midpoint(_ a: [Character], _ b: [Character]?) -> [Character] {
        if let b {
            // Skip the shared prefix, treating a missing digit in `a` as "0".
            var n = 0
            while n < b.count, (n < a.count ? a[n] : "0") == b[n] {
                n += 1
            }
            if n > 0 {
                let rest = midpoint(Array(a.dropFirst(n)), Array(b.dropFirst(n)))
                return Array(b.prefix(n)) + rest
            }
        }
        let da = a.isEmpty ? 0 : index(a[0])
        let db = b.map { index($0[0]) } ?? digits.count
        if db - da > 1 {
            return [digits[(da + db) / 2]]
        }
        // Adjacent first digits.
        if let b, b.count > 1 {
            return [b[0]]
        }
        return [digits[da]] + midpoint(Array(a.dropFirst()), nil)
    }
}
