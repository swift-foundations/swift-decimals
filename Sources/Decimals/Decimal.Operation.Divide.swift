extension Decimal.Operation where Value == Decimal.Format32 {
    public func divide(
        _ other: Value,
        context: Decimal.Context = .format32
    ) -> Decimal.Outcome<Value> {
        let a = base
        let b = other

        let resultSign: Decimal.Sign = (a.sign == b.sign) ? .positive : .negative

        // 1. Handle NaN propagation
        if a.test.signaling || b.test.signaling {
            let payload = a.test.signaling ? Decimal.Payload(UInt64(a.extractCoefficient())) : Decimal.Payload(UInt64(b.extractCoefficient()))
            return Decimal.Outcome(value: .nan(kind: .quiet, payload: payload), status: .invalid)
        }

        if a.test.nan {
            return Decimal.Outcome(value: a, status: .none)
        }
        if b.test.nan {
            return Decimal.Outcome(value: b, status: .none)
        }

        // 2. Handle infinity cases
        if a.test.infinite {
            if b.test.infinite {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }

        // 3. Handle division by zero
        if b.test.zero {
            if a.test.zero {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .divide)
        }

        // 4. Handle zero dividend
        if a.test.zero {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 5. x / ∞ = 0
        if b.test.infinite {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 6. Extract components
        var coeffA = UInt64(a.extractCoefficient())
        let coeffB = UInt64(b.extractCoefficient())
        var expA = a.extractExponent()
        let expB = b.extractExponent()

        // 7. Scale dividend for precision
        let targetDigits = context.precision.rawValue + 2

        var digitsA = 0
        var temp = coeffA
        while temp > 0 {
            digitsA += 1
            temp /= 10
        }

        let scaleUp = targetDigits + 7 - digitsA  // 7 is max digits in coeffB
        if scaleUp > 0 {
            for _ in 0..<scaleUp {
                coeffA *= 10
            }
            // No `-=` overload for Decimal.Exponent; `-` here is heterogeneous (Self, Int).
            // swiftlint:disable:next shorthand_operator
            expA = expA - scaleUp
        }

        // 8. Perform division
        let quotient = coeffA / coeffB
        let remainder = coeffA % coeffB

        let resultExp = expA - expB

        // 9. Round to precision
        var status: Decimal.Status = .none
        if remainder != 0 {
            status = .inexact
        }

        let (finalCoeff, finalExp, roundStatus) = Decimals.Rounding.round(
            coefficient: quotient,
            exponent: resultExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )
        status = status.union(roundStatus)

        // 10. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 11. Check for underflow
        if finalExp < context.minExponent {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: status.union(Decimal.Status.underflow))
        }

        // 12. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func divide(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try divide(other, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format64 {
    public func divide(
        _ other: Value,
        context: Decimal.Context = .format64
    ) -> Decimal.Outcome<Value> {
        let a = base
        let b = other

        // Result sign: positive if same signs, negative if different
        let resultSign: Decimal.Sign = (a.sign == b.sign) ? .positive : .negative

        // 1. Handle NaN propagation
        if a.test.signaling || b.test.signaling {
            let payload = a.test.signaling ? Decimal.Payload(a.extractCoefficient()) : Decimal.Payload(b.extractCoefficient())
            return Decimal.Outcome(value: .nan(kind: .quiet, payload: payload), status: .invalid)
        }

        if a.test.nan {
            return Decimal.Outcome(value: a, status: .none)
        }
        if b.test.nan {
            return Decimal.Outcome(value: b, status: .none)
        }

        // 2. Handle infinity cases
        if a.test.infinite {
            if b.test.infinite {
                // ∞ / ∞ = NaN (invalid)
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }

        // 3. Handle division by zero
        if b.test.zero {
            if a.test.zero {
                // 0 / 0 = NaN (invalid)
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            // x / 0 = ∞ (divide by zero)
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .divide)
        }

        // 4. Handle zero dividend
        if a.test.zero {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 5. x / ∞ = 0
        if b.test.infinite {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 6. Extract components
        var coeffA = UInt128(a.extractCoefficient())
        let coeffB = UInt128(b.extractCoefficient())
        var expA = a.extractExponent()
        let expB = b.extractExponent()

        // 7. Scale dividend to get enough precision for division
        // We need at least (precision + 1) digits in the quotient for proper rounding
        let targetDigits = context.precision.rawValue + 2

        // Count digits in coeffA
        var digitsA = 0
        var temp = coeffA
        while temp > 0 {
            digitsA += 1
            temp /= 10
        }

        // Scale up coeffA if needed
        let scaleUp = targetDigits + 16 - digitsA  // 16 is max digits in coeffB
        if scaleUp > 0 {
            for _ in 0..<scaleUp {
                coeffA *= 10
            }
            // No `-=` overload for Decimal.Exponent; `-` here is heterogeneous (Self, Int).
            // swiftlint:disable:next shorthand_operator
            expA = expA - scaleUp
        }

        // 8. Perform division
        let quotient = coeffA / coeffB
        let remainder = coeffA % coeffB

        // Calculate result exponent
        let resultExp = expA - expB

        // 9. Round to precision
        var status: Decimal.Status = .none
        if remainder != 0 {
            status = .inexact
        }

        let (finalCoeff, finalExp, roundStatus) = Decimals.Rounding.round(
            coefficient: quotient,
            exponent: resultExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )
        status = status.union(roundStatus)

        // 10. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 11. Check for underflow
        if finalExp < context.minExponent {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: status.union(Decimal.Status.underflow))
        }

        // 12. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func divide(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try divide(other, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format128 {
    public func divide(
        _ other: Value,
        context: Decimal.Context = .format128
    ) -> Decimal.Outcome<Value> {
        let a = base
        let b = other

        let resultSign: Decimal.Sign = (a.sign == b.sign) ? .positive : .negative

        // 1. Handle NaN propagation
        if a.test.signaling || b.test.signaling {
            let payload = a.test.signaling ? Decimal.Payload(UInt64(truncatingIfNeeded: a.extractCoefficient())) : Decimal.Payload(UInt64(truncatingIfNeeded: b.extractCoefficient()))
            return Decimal.Outcome(value: .nan(kind: .quiet, payload: payload), status: .invalid)
        }

        if a.test.nan {
            return Decimal.Outcome(value: a, status: .none)
        }
        if b.test.nan {
            return Decimal.Outcome(value: b, status: .none)
        }

        // 2. Handle infinity cases
        if a.test.infinite {
            if b.test.infinite {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }

        // 3. Handle division by zero
        if b.test.zero {
            if a.test.zero {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .divide)
        }

        // 4. Handle zero dividend
        if a.test.zero {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 5. x / ∞ = 0
        if b.test.infinite {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 6. Extract components
        var coeffA = a.extractCoefficient()
        let coeffB = b.extractCoefficient()
        var expA = a.extractExponent()
        let expB = b.extractExponent()

        // 7. Scale dividend for precision
        let targetDigits = context.precision.rawValue + 2

        var digitsA = 0
        var temp = coeffA
        while temp > 0 {
            digitsA += 1
            temp /= 10
        }

        let scaleUp = targetDigits + 34 - digitsA  // 34 is max digits in coeffB
        if scaleUp > 0 {
            for _ in 0..<scaleUp {
                coeffA *= 10
            }
            // No `-=` overload for Decimal.Exponent; `-` here is heterogeneous (Self, Int).
            // swiftlint:disable:next shorthand_operator
            expA = expA - scaleUp
        }

        // 8. Perform division
        let quotient = coeffA / coeffB
        let remainder = coeffA % coeffB

        let resultExp = expA - expB

        // 9. Round to precision
        var status: Decimal.Status = .none
        if remainder != 0 {
            status = .inexact
        }

        let (finalCoeff, finalExp, roundStatus) = Decimals.Rounding.round128(
            coefficient: quotient,
            exponent: resultExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )
        status = status.union(roundStatus)

        // 10. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 11. Check for underflow
        if finalExp < context.minExponent {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: status.union(Decimal.Status.underflow))
        }

        // 12. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func divide(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try divide(other, context: context).trapped(by: context.traps)
    }
}
