// Decimals.Rounding.swift
// swift-decimals
//
// Rounding utilities for decimal arithmetic

extension Decimals {
    /// Rounding utilities for decimal coefficient adjustment
    public enum Rounding {}
}

extension Decimals.Rounding {
    /// The number of significant decimal digits in `coefficient` (`0` has `0` digits).
    ///
    /// Shared by callers that need to make a digit-position-aware decision
    /// before rounding (e.g. `add()`/`fuse()`'s exact-vs-drop exponent-gap
    /// test) — the same digit-counting loop this file already runs
    /// internally to decide how many digits a rounding pass must remove.
    static func digitCount(_ coefficient: UInt64) -> Int {
        var digits = 0
        var temp = coefficient
        while temp > 0 {
            digits += 1
            temp /= 10
        }
        return digits
    }

    /// The number of significant decimal digits in `coefficient` (`0` has `0` digits).
    ///
    /// See the `UInt64` overload's documentation.
    static func digitCount(_ coefficient: UInt128) -> Int {
        var digits = 0
        var temp = coefficient
        while temp > 0 {
            digits += 1
            temp /= 10
        }
        return digits
    }
}

extension Decimals.Rounding {
    /// Round a Format32 coefficient to fit in the specified precision
    ///
    /// - Parameters:
    ///   - coefficient: The coefficient to round (may exceed precision)
    ///   - exponent: The current exponent
    ///   - sign: The sign of the value
    ///   - mode: The rounding mode to apply
    ///   - precision: The target precision
    ///   - sticky: True if the caller already discarded nonzero, lower-order
    ///     information before computing `coefficient` (e.g. a division remainder
    ///     beyond the guard digits retained in the quotient). When true, an exact
    ///     tie at the rounding boundary is known to actually be slightly more than
    ///     half, which avoids double-rounding a value that was already truncated
    ///     once by the caller.
    /// - Returns: Tuple of (rounded coefficient, adjusted exponent, status flags)
    public static func round(
        coefficient: UInt64,
        exponent: Decimal.Exponent,
        sign: Decimal.Sign,
        rounding: Decimal.Rounding,
        precision: Decimal.Precision,
        sticky: Bool = false
    ) -> (coefficient: UInt32, exponent: Decimal.Exponent, status: Decimal.Status) {
        let c = coefficient
        var e = exponent
        var status: Decimal.Status = .none

        // Calculate number of digits
        var digits = 0
        var temp = c
        while temp > 0 {
            digits += 1
            temp /= 10
        }

        // If coefficient fits in precision, no rounding needed — but a sticky
        // (already-discarded) remainder still makes the result inexact.
        if digits <= precision.rawValue {
            return (UInt32(truncatingIfNeeded: c), e, sticky ? .inexact : status)
        }

        // Need to round off (digits - precision) digits
        let roundDigits = digits - precision.rawValue

        // Calculate divisor
        var divisor: UInt64 = 1
        for _ in 0..<roundDigits {
            divisor *= 10
        }

        let quotient = c / divisor
        let remainder = c % divisor
        let halfDivisor = divisor / 2

        // A sticky remainder means the true (pre-truncation) value is strictly
        // greater than what `remainder` alone shows, so it can never be an exact
        // tie and any zero remainder is actually still a positive one.
        let remainderPositive = remainder > 0 || sticky
        let isAboveHalf = remainder > halfDivisor || (sticky && remainder == halfDivisor)
        let isExactHalf = remainder == halfDivisor && !sticky

        // Determine if we need to round up
        var roundUp = false
        switch rounding {
        case .ceiling:
            roundUp = remainderPositive && sign == .positive
        case .floor:
            roundUp = remainderPositive && sign == .negative
        case .down:
            roundUp = false
        case .up:
            roundUp = remainderPositive
        case .even:
            if isAboveHalf {
                roundUp = true
            } else if isExactHalf {
                roundUp = (quotient % 2) != 0
            }
        case .away:
            roundUp = isAboveHalf || isExactHalf
        case .toward:
            roundUp = isAboveHalf
        }

        var result = quotient
        if roundUp {
            result += 1
        }

        if remainderPositive {
            status = .inexact
        }

        // No `+=` overload for Decimal.Exponent; `+` here is heterogeneous (Self, Int).
        // swiftlint:disable:next shorthand_operator
        e = e + roundDigits

        // Check if rounding caused overflow of coefficient
        if result > UInt64(Decimal.Format32.coefficientMax()) {
            result /= 10
            // No `+=` overload for Decimal.Exponent; `+` here is heterogeneous (Self, Int).
            // swiftlint:disable:next shorthand_operator
            e = e + 1
        }

        return (UInt32(truncatingIfNeeded: result), e, status)
    }

    /// Round a Format64 coefficient to fit in the specified precision
    ///
    /// - Parameter sticky: See the Format32 `round(coefficient:exponent:sign:rounding:precision:sticky:)`
    ///   overload's documentation.
    public static func round(
        coefficient: UInt128,
        exponent: Decimal.Exponent,
        sign: Decimal.Sign,
        rounding: Decimal.Rounding,
        precision: Decimal.Precision,
        sticky: Bool = false
    ) -> (coefficient: UInt64, exponent: Decimal.Exponent, status: Decimal.Status) {
        let c = coefficient
        var e = exponent
        var status: Decimal.Status = .none

        // Calculate number of digits
        var digits = 0
        var temp = c
        while temp > 0 {
            digits += 1
            temp /= 10
        }

        // If coefficient fits in precision, no rounding needed — but a sticky
        // (already-discarded) remainder still makes the result inexact.
        if digits <= precision.rawValue {
            return (UInt64(truncatingIfNeeded: c), e, sticky ? .inexact : status)
        }

        // Need to round off (digits - precision) digits
        let roundDigits = digits - precision.rawValue

        // Calculate divisor
        var divisor: UInt128 = 1
        for _ in 0..<roundDigits {
            divisor *= 10
        }

        let quotient = c / divisor
        let remainder = c % divisor
        let halfDivisor = divisor / 2

        // A sticky remainder means the true (pre-truncation) value is strictly
        // greater than what `remainder` alone shows, so it can never be an exact
        // tie and any zero remainder is actually still a positive one.
        let remainderPositive = remainder > 0 || sticky
        let isAboveHalf = remainder > halfDivisor || (sticky && remainder == halfDivisor)
        let isExactHalf = remainder == halfDivisor && !sticky

        // Determine if we need to round up
        var roundUp = false
        switch rounding {
        case .ceiling:
            roundUp = remainderPositive && sign == .positive
        case .floor:
            roundUp = remainderPositive && sign == .negative
        case .down:
            roundUp = false
        case .up:
            roundUp = remainderPositive
        case .even:
            if isAboveHalf {
                roundUp = true
            } else if isExactHalf {
                roundUp = (quotient % 2) != 0
            }
        case .away:
            roundUp = isAboveHalf || isExactHalf
        case .toward:
            roundUp = isAboveHalf
        }

        var result = quotient
        if roundUp {
            result += 1
        }

        if remainderPositive {
            status = .inexact
        }

        // No `+=` overload for Decimal.Exponent; `+` here is heterogeneous (Self, Int).
        // swiftlint:disable:next shorthand_operator
        e = e + roundDigits

        // Check if rounding caused overflow of coefficient
        if result > UInt128(Decimal.Format64.coefficientMax()) {
            result /= 10
            // No `+=` overload for Decimal.Exponent; `+` here is heterogeneous (Self, Int).
            // swiftlint:disable:next shorthand_operator
            e = e + 1
        }

        return (UInt64(truncatingIfNeeded: result), e, status)
    }

    /// Round a Format128 coefficient to fit in the specified precision
    ///
    /// - Parameter sticky: See the Format32 `round(coefficient:exponent:sign:rounding:precision:sticky:)`
    ///   overload's documentation.
    public static func round128(
        coefficient: UInt128,
        exponent: Decimal.Exponent,
        sign: Decimal.Sign,
        rounding: Decimal.Rounding,
        precision: Decimal.Precision,
        sticky: Bool = false
    ) -> (coefficient: UInt128, exponent: Decimal.Exponent, status: Decimal.Status) {
        let c = coefficient
        var e = exponent
        var status: Decimal.Status = .none

        // Calculate number of digits
        var digits = 0
        var temp = c
        while temp > 0 {
            digits += 1
            temp /= 10
        }

        // If coefficient fits in precision, no rounding needed — but a sticky
        // (already-discarded) remainder still makes the result inexact.
        if digits <= precision.rawValue {
            return (c, e, sticky ? .inexact : status)
        }

        // Need to round off (digits - precision) digits
        let roundDigits = digits - precision.rawValue

        // Calculate divisor
        var divisor: UInt128 = 1
        for _ in 0..<roundDigits {
            divisor *= 10
        }

        let quotient = c / divisor
        let remainder = c % divisor
        let halfDivisor = divisor / 2

        // A sticky remainder means the true (pre-truncation) value is strictly
        // greater than what `remainder` alone shows, so it can never be an exact
        // tie and any zero remainder is actually still a positive one.
        let remainderPositive = remainder > 0 || sticky
        let isAboveHalf = remainder > halfDivisor || (sticky && remainder == halfDivisor)
        let isExactHalf = remainder == halfDivisor && !sticky

        // Determine if we need to round up
        var roundUp = false
        switch rounding {
        case .ceiling:
            roundUp = remainderPositive && sign == .positive
        case .floor:
            roundUp = remainderPositive && sign == .negative
        case .down:
            roundUp = false
        case .up:
            roundUp = remainderPositive
        case .even:
            if isAboveHalf {
                roundUp = true
            } else if isExactHalf {
                roundUp = (quotient % 2) != 0
            }
        case .away:
            roundUp = isAboveHalf || isExactHalf
        case .toward:
            roundUp = isAboveHalf
        }

        var result = quotient
        if roundUp {
            result += 1
        }

        if remainderPositive {
            status = .inexact
        }

        // No `+=` overload for Decimal.Exponent; `+` here is heterogeneous (Self, Int).
        // swiftlint:disable:next shorthand_operator
        e = e + roundDigits

        // Check if rounding caused overflow of coefficient
        if result > Decimal.Format128.coefficientMax() {
            result /= 10
            // No `+=` overload for Decimal.Exponent; `+` here is heterogeneous (Self, Int).
            // swiftlint:disable:next shorthand_operator
            e = e + 1
        }

        return (result, e, status)
    }
}
