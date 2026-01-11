extension Decimal.Operation where Value == Decimal.Format32 {
    public func add(
        _ other: Value,
        context: Decimal.Context = .format32
    ) -> Decimal.Outcome<Value> {
        let a = base
        let b = other

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
                if a.sign != b.sign {
                    return Decimal.Outcome(value: .nan(), status: .invalid)
                }
            }
            return Decimal.Outcome(value: a, status: .none)
        }
        if b.test.infinite {
            return Decimal.Outcome(value: b, status: .none)
        }

        // 3. Handle zero cases
        if a.test.zero && b.test.zero {
            let resultSign: Decimal.Sign = (a.sign == .negative && b.sign == .negative) ? .negative :
                                           (context.rounding == .floor ? .negative : .positive)
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }
        if a.test.zero {
            return Decimal.Outcome(value: b, status: .none)
        }
        if b.test.zero {
            return Decimal.Outcome(value: a, status: .none)
        }

        // 4. Extract components
        let signA = a.sign
        let signB = b.sign
        var coeffA = UInt64(a.extractCoefficient())
        var coeffB = UInt64(b.extractCoefficient())
        var expA = a.extractExponent()
        var expB = b.extractExponent()

        // 5. Align exponents
        if expA < expB {
            let diff = expB - expA
            if diff.rawValue > 20 {
                return Decimal.Outcome(value: b, status: .none)
            }
            for _ in 0..<diff.rawValue {
                coeffB *= 10
            }
            expB = expA
        } else if expB < expA {
            let diff = expA - expB
            if diff.rawValue > 20 {
                return Decimal.Outcome(value: a, status: .none)
            }
            for _ in 0..<diff.rawValue {
                coeffA *= 10
            }
            expA = expB
        }

        // 6. Perform addition/subtraction
        let resultSign: Decimal.Sign
        let resultCoeff: UInt64

        if signA == signB {
            resultSign = signA
            resultCoeff = coeffA + coeffB
        } else {
            if coeffA >= coeffB {
                resultSign = signA
                resultCoeff = coeffA - coeffB
            } else {
                resultSign = signB
                resultCoeff = coeffB - coeffA
            }
        }

        if resultCoeff == 0 {
            let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
            return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
        }

        // 7. Round to precision
        let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
            coefficient: resultCoeff,
            exponent: expA,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        // 8. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 9. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func add(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try add(other, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format64 {
    public func add(
        _ other: Value,
        context: Decimal.Context = .format64
    ) -> Decimal.Outcome<Value> {
        let a = base
        let b = other

        // 1. Handle NaN propagation
        if a.test.signaling || b.test.signaling {
            // Signaling NaN raises invalid and returns quiet NaN
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
                // ∞ + ∞ = ∞, but ∞ + (-∞) = NaN
                if a.sign != b.sign {
                    return Decimal.Outcome(value: .nan(), status: .invalid)
                }
            }
            return Decimal.Outcome(value: a, status: .none)
        }
        if b.test.infinite {
            return Decimal.Outcome(value: b, status: .none)
        }

        // 3. Handle zero cases
        if a.test.zero && b.test.zero {
            // 0 + 0: sign depends on rounding mode
            let resultSign: Decimal.Sign = (a.sign == .negative && b.sign == .negative) ? .negative :
                                           (context.rounding == .floor ? .negative : .positive)
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }
        if a.test.zero {
            return Decimal.Outcome(value: b, status: .none)
        }
        if b.test.zero {
            return Decimal.Outcome(value: a, status: .none)
        }

        // 4. Extract components
        let signA = a.sign
        let signB = b.sign
        var coeffA = UInt128(a.extractCoefficient())
        var coeffB = UInt128(b.extractCoefficient())
        var expA = a.extractExponent()
        var expB = b.extractExponent()

        // 5. Align exponents (scale smaller exponent up)
        if expA < expB {
            let diff = expB - expA
            if diff.rawValue > 38 {
                // B is so much larger that A is negligible
                return Decimal.Outcome(value: b, status: .none)
            }
            for _ in 0..<diff.rawValue {
                coeffB *= 10
            }
            expB = expA
        } else if expB < expA {
            let diff = expA - expB
            if diff.rawValue > 38 {
                // A is so much larger that B is negligible
                return Decimal.Outcome(value: a, status: .none)
            }
            for _ in 0..<diff.rawValue {
                coeffA *= 10
            }
            expA = expB
        }

        // 6. Perform addition/subtraction
        let resultSign: Decimal.Sign
        let resultCoeff: UInt128

        if signA == signB {
            // Same sign: add magnitudes
            resultSign = signA
            resultCoeff = coeffA + coeffB
        } else {
            // Different signs: subtract magnitudes
            if coeffA >= coeffB {
                resultSign = signA
                resultCoeff = coeffA - coeffB
            } else {
                resultSign = signB
                resultCoeff = coeffB - coeffA
            }
        }

        // Handle zero result
        if resultCoeff == 0 {
            let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
            return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
        }

        // 7. Round to precision
        let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
            coefficient: resultCoeff,
            exponent: expA,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        // 8. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 9. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func add(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try add(other, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format128 {
    public func add(
        _ other: Value,
        context: Decimal.Context = .format128
    ) -> Decimal.Outcome<Value> {
        let a = base
        let b = other

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
                if a.sign != b.sign {
                    return Decimal.Outcome(value: .nan(), status: .invalid)
                }
            }
            return Decimal.Outcome(value: a, status: .none)
        }
        if b.test.infinite {
            return Decimal.Outcome(value: b, status: .none)
        }

        // 3. Handle zero cases
        if a.test.zero && b.test.zero {
            let resultSign: Decimal.Sign = (a.sign == .negative && b.sign == .negative) ? .negative :
                                           (context.rounding == .floor ? .negative : .positive)
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }
        if a.test.zero {
            return Decimal.Outcome(value: b, status: .none)
        }
        if b.test.zero {
            return Decimal.Outcome(value: a, status: .none)
        }

        // 4. Extract components
        let signA = a.sign
        let signB = b.sign
        var coeffA = a.extractCoefficient()
        var coeffB = b.extractCoefficient()
        var expA = a.extractExponent()
        var expB = b.extractExponent()

        // 5. Align exponents
        if expA < expB {
            let diff = expB - expA
            if diff.rawValue > 70 {
                return Decimal.Outcome(value: b, status: .none)
            }
            for _ in 0..<diff.rawValue {
                coeffB *= 10
            }
            expB = expA
        } else if expB < expA {
            let diff = expA - expB
            if diff.rawValue > 70 {
                return Decimal.Outcome(value: a, status: .none)
            }
            for _ in 0..<diff.rawValue {
                coeffA *= 10
            }
            expA = expB
        }

        // 6. Perform addition/subtraction
        let resultSign: Decimal.Sign
        let resultCoeff: UInt128

        if signA == signB {
            resultSign = signA
            resultCoeff = coeffA + coeffB
        } else {
            if coeffA >= coeffB {
                resultSign = signA
                resultCoeff = coeffA - coeffB
            } else {
                resultSign = signB
                resultCoeff = coeffB - coeffA
            }
        }

        if resultCoeff == 0 {
            let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
            return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
        }

        // 7. Round to precision
        let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
            coefficient: resultCoeff,
            exponent: expA,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        // 8. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 9. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func add(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try add(other, context: context).trapped(by: context.traps)
    }
}
