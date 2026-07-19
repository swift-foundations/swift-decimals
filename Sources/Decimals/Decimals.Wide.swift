// Decimals.Wide.swift
// swift-decimals
//
// A 256-bit unsigned integer scratch type, used only as an exact
// double-width intermediate for exponent-alignment scaling in add()/fuse()
// when the working format's own coefficient type (UInt64/UInt128) does not
// have enough headroom above the format's precision to guarantee a
// discarded operand is negligible (F-002/F-003 revision 1). Not public API:
// this exists purely to let add()/fuse() compute an exact sum before
// rounding once, then reduce back down to the working coefficient width.

extension Decimals {
    /// A 256-bit unsigned integer formed from two `UInt128` limbs.
    struct Wide: Sendable, Hashable {
        /// The high 128 bits.
        var high: UInt128

        /// The low 128 bits.
        var low: UInt128

        init(high: UInt128, low: UInt128) {
            self.high = high
            self.low = low
        }
    }
}

// MARK: - Construction

extension Decimals.Wide {
    /// Widens a `UInt128` coefficient into the low limb of a 256-bit value.
    init(_ value: UInt128) {
        self.init(high: 0, low: value)
    }
}

// MARK: - Comparison

extension Decimals.Wide: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.high != rhs.high { return lhs.high < rhs.high }
        return lhs.low < rhs.low
    }
}

extension Decimals.Wide {
    var isZero: Bool { high == 0 && low == 0 }
}

// MARK: - Arithmetic

extension Decimals.Wide {
    /// Returns `self * 10`, trapping if the product would not fit in 256 bits.
    ///
    /// Callers only ever multiply within the bounded "exact window" (exponent
    /// gap below `precision + 2`), where the total digit count of the widened
    /// operand provably stays far under 256 bits' ~77-digit capacity — a trap
    /// here would mean that bound was violated, which is a programmer error,
    /// not a legal-input condition.
    func multipliedBy10() -> Self {
        let (carry, newLow) = low.multipliedFullWidth(by: 10)
        let (highTimesTen, highOverflow) = high.multipliedReportingOverflow(by: 10)
        let (newHigh, carryOverflow) = highTimesTen.addingReportingOverflow(carry)
        precondition(!highOverflow && !carryOverflow, "Decimals.Wide multiplication overflowed 256 bits")
        return Self(high: newHigh, low: newLow)
    }

    /// Returns `value * 10^count`.
    static func multiplied(_ value: Self, byPowerOf10 count: Int) -> Self {
        var result = value
        for _ in 0..<count {
            result = result.multipliedBy10()
        }
        return result
    }

    /// Returns `self + other`, trapping if the sum would not fit in 256 bits.
    func adding(_ other: Self) -> Self {
        let (lowSum, lowCarry) = low.addingReportingOverflow(other.low)
        let (highSum, highOverflow) = high.addingReportingOverflow(other.high)
        let (highSum2, carryOverflow) = highSum.addingReportingOverflow(lowCarry ? 1 : 0)
        precondition(!highOverflow && !carryOverflow, "Decimals.Wide addition overflowed 256 bits")
        return Self(high: highSum2, low: lowSum)
    }

    /// Returns `self - other`.
    ///
    /// - Precondition: `self >= other`. Callers compare before subtracting
    ///   (the sign of a decimal subtraction is decided by which magnitude is
    ///   larger), so this never needs to represent a negative result.
    func subtracting(_ other: Self) -> Self {
        precondition(self >= other, "Decimals.Wide subtraction requires self >= other")
        let (lowDiff, lowBorrow) = low.subtractingReportingOverflow(other.low)
        let (highDiff, _) = high.subtractingReportingOverflow(other.high)
        // A second precondition guarding this borrow used to read
        // `!highBorrow || !borrowOverflow` — but the `self >= other`
        // precondition above already forces `highBorrow` to always be
        // `false` here (either `high > other.high`, in which case
        // `subtractingReportingOverflow` cannot borrow, or `high ==
        // other.high` with `low >= other.low`, which also cannot borrow),
        // making that second check a tautology (`true || x` regardless of
        // `x`) rather than a real assertion. Removed; this subtraction
        // cannot underflow given the precondition already enforced above.
        let (highDiff2, _) = highDiff.subtractingReportingOverflow(lowBorrow ? 1 : 0)
        return Self(high: highDiff2, low: lowDiff)
    }

    /// Returns `self / 10` and `self % 10`, computed exactly across both limbs.
    func dividedBy10() -> (quotient: Self, remainder: UInt128) {
        let (highQuotient, highRemainder) = high.quotientAndRemainder(dividingBy: 10)
        // `highRemainder` is always in 0...9, satisfying `dividingFullWidth`'s
        // `dividend.high < divisor` precondition for divisor 10.
        let (lowQuotient, lowRemainder) = UInt128(10).dividingFullWidth((high: highRemainder, low: low))
        return (Self(high: highQuotient, low: lowQuotient), lowRemainder)
    }

    /// Repeatedly divides by 10 until the value is `<= limit`, returning the
    /// reduced coefficient, the number of digits shifted off (to add back onto
    /// the associated exponent), and whether any discarded digit was nonzero
    /// (to fold into a rounding kernel's `sticky` parameter).
    ///
    /// Callers pass the working coefficient type's own maximum (`UInt64.max`
    /// widened to `UInt128`, or `UInt128.max` itself) — the format's actual
    /// `coefficientMax()` is smaller still and is enforced separately by the
    /// rounding kernel this feeds into.
    func reduced(toFitBelowOrEqual limit: UInt128) -> (coefficient: UInt128, shift: Int, sticky: Bool) {
        var value = self
        var shift = 0
        var sticky = false
        while value.high != 0 || value.low > limit {
            let (quotient, remainder) = value.dividedBy10()
            if remainder != 0 { sticky = true }
            value = quotient
            shift += 1
        }
        return (value.low, shift, sticky)
    }

    /// Repeatedly divides by 10 until the value fits in a single `UInt128`
    /// (i.e. `high == 0`). See `reduced(toFitBelowOrEqual:)`.
    func reducedToFitUInt128() -> (coefficient: UInt128, shift: Int, sticky: Bool) {
        reduced(toFitBelowOrEqual: .max)
    }
}
