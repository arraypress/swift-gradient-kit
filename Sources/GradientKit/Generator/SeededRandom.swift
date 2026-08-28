//
//  SeededRandom.swift
//  GradientKit
//
//  SplitMix64 with its own distribution helpers, so a seed reproduces the
//  same wallpaper on every platform and Swift version (the stdlib's
//  `random(in:using:)` algorithms are not a stability promise).
//

import Foundation

public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let count = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % count)
    }

    public mutating func bool(_ probability: Double = 0.5) -> Bool {
        unit() < probability
    }

    public mutating func sign() -> Double { bool() ? 1 : -1 }

    public mutating func pick<T>(_ items: [T]) -> T {
        precondition(!items.isEmpty)
        return items[int(in: 0...(items.count - 1))]
    }

    /// Gaussian-ish jitter (sum of three uniforms), mean 0, roughly ±spread.
    public mutating func jitter(_ spread: Double) -> Double {
        (unit() + unit() + unit() - 1.5) / 1.5 * spread
    }

    /// A fresh generator derived from this one — for independent sub-streams.
    public mutating func fork() -> SeededRandom { SeededRandom(seed: next()) }
}
