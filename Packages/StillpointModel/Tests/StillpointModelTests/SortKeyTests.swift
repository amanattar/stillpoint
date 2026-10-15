import Testing
@testable import StillpointModel

struct SortKeyTests {
    @Test func firstKeyIsMiddle() {
        #expect(SortKey.between(nil, nil) == "V")
    }

    @Test func betweenIsStrictlyBetween() {
        let pairs: [(String?, String?)] = [(nil, "V"), ("V", nil), ("V", "W"), ("V", "V1"), ("z", nil), ("Vz", "W"), (nil, "01")]
        for (a, b) in pairs {
            let k = SortKey.between(a, b)
            if let a { #expect(a < k, "\(a) < \(k)") }
            if let b { #expect(k < b, "\(k) < \(b)") }
            #expect(!k.hasSuffix("0"))
        }
    }

    @Test func sequenceIsAscending() {
        let keys = SortKey.sequence(count: 50, after: "A", before: "B")
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == 50)
        #expect(keys.allSatisfy { $0 > "A" && $0 < "B" })
    }

    @Test func tenThousandRandomInsertsStayOrderedAndUnique() {
        var rng = SeededGenerator(seed: 42)
        var keys: [String] = []
        for _ in 0..<10_000 {
            let i = Int.random(in: 0...keys.count, using: &rng)
            let lower = i > 0 ? keys[i - 1] : nil
            let upper = i < keys.count ? keys[i] : nil
            keys.insert(SortKey.between(lower, upper), at: i)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
        #expect(keys.map(\.count).max()! < 40)
    }

    @Test func repeatedAppendGrowsSlowly() {
        var last: String? = nil
        for _ in 0..<1_000 { last = SortKey.between(last, nil) }
        #expect(last!.count < 40)
    }
}

/// Deterministic RNG (SplitMix64) so failures are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SortKeyTests {
    @Test func repeatedPrependGrowsSlowly() {
        var first: String? = nil
        var keys: [String] = []
        for _ in 0..<1_000 {
            first = SortKey.between(nil, first)
            keys.insert(first!, at: 0)
        }
        #expect(keys == keys.sorted())
        #expect(keys.allSatisfy { !$0.hasSuffix("0") })
        #expect(first!.count < 40)
    }
}
