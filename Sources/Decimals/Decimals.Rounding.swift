// Decimals.Rounding.swift
// swift-decimals
//
// Rounding utilities for decimal arithmetic

extension Decimals {
    /// Rounding utilities for decimal coefficient adjustment
    public enum Rounding {}
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
    /// - Returns: Tuple of (rounded coefficient, adjusted exponent, status flags)
    public static func round(
        coefficient: UInt64,
        exponent: Decimal.Exponent,
        sign: Decimal.Sign,
        rounding: Decimal.Rounding,
        precision: Decimal.Precision
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

        // If coefficient fits in precision, no rounding needed
        if digits <= precision.rawValue {
            return (UInt32(truncatingIfNeeded: c), e, status)
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

        // Determine if we need to round up
        var roundUp = false
        switch rounding {
        case .ceiling:
            roundUp = remainder > 0 && sign == .positive
        case .floor:
            roundUp = remainder > 0 && sign == .negative
        case .down:
            roundUp = false
        case .up:
            roundUp = remainder > 0
        case .even:
            if remainder > halfDivisor {
                roundUp = true
            } else if remainder == halfDivisor {
                roundUp = (quotient % 2) != 0
            }
        case .away:
            roundUp = remainder >= halfDivisor
        case .toward:
            roundUp = remainder > halfDivisor
        }

        var result = quotient
        if roundUp {
            result += 1
        }

        if remainder > 0 {
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
    public static func round(
        coefficient: UInt128,
        exponent: Decimal.Exponent,
        sign: Decimal.Sign,
        rounding: Decimal.Rounding,
        precision: Decimal.Precision
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

        // If coefficient fits in precision, no rounding needed
        if digits <= precision.rawValue {
            return (UInt64(truncatingIfNeeded: c), e, status)
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

        // Determine if we need to round up
        var roundUp = false
        switch rounding {
        case .ceiling:
            roundUp = remainder > 0 && sign == .positive
        case .floor:
            roundUp = remainder > 0 && sign == .negative
        case .down:
            roundUp = false
        case .up:
            roundUp = remainder > 0
        case .even:
            if remainder > halfDivisor {
                roundUp = true
            } else if remainder == halfDivisor {
                roundUp = (quotient % 2) != 0
            }
        case .away:
            roundUp = remainder >= halfDivisor
        case .toward:
            roundUp = remainder > halfDivisor
        }

        var result = quotient
        if roundUp {
            result += 1
        }

        if remainder > 0 {
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
    public static func round128(
        coefficient: UInt128,
        exponent: Decimal.Exponent,
        sign: Decimal.Sign,
        rounding: Decimal.Rounding,
        precision: Decimal.Precision
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

        // If coefficient fits in precision, no rounding needed
        if digits <= precision.rawValue {
            return (c, e, status)
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

        // Determine if we need to round up
        var roundUp = false
        switch rounding {
        case .ceiling:
            roundUp = remainder > 0 && sign == .positive
        case .floor:
            roundUp = remainder > 0 && sign == .negative
        case .down:
            roundUp = false
        case .up:
            roundUp = remainder > 0
        case .even:
            if remainder > halfDivisor {
                roundUp = true
            } else if remainder == halfDivisor {
                roundUp = (quotient % 2) != 0
            }
        case .away:
            roundUp = remainder >= halfDivisor
        case .toward:
            roundUp = remainder > halfDivisor
        }

        var result = quotient
        if roundUp {
            result += 1
        }

        if remainder > 0 {
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
