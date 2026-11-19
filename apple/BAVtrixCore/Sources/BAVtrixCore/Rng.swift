/// Small deterministic xorshift generator (same family as the Windows version).
public struct Rng {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed | 1
    }

    public mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x &* 0x2545_F491_4F6C_DD1D
    }

    /// Uniform integer in 0..<n (0 when n <= 0).
    public mutating func below(_ n: Int) -> Int {
        if n <= 0 { return 0 }
        return Int((next() >> 11) % UInt64(n))
    }

    /// Uniform float in 0..<1.
    public mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
