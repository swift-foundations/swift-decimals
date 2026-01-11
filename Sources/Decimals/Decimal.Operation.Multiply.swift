extension Decimal.Operation where Value == Decimal.Format32 {
    public func multiply(
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
            if b.test.zero {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }
        if b.test.infinite {
            if a.test.zero {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }

        // 3. Handle zero cases
        if a.test.zero || b.test.zero {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 4. Extract components
        let coeffA = UInt64(a.extractCoefficient())
        let coeffB = UInt64(b.extractCoefficient())
        let expA = a.extractExponent()
        let expB = b.extractExponent()

        // 5. Multiply coefficients and add exponents
        let resultCoeff = coeffA * coeffB
        let resultExp = expA + expB

        // 6. Round to precision
        let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
            coefficient: resultCoeff,
            exponent: resultExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        // 7. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 8. Check for underflow
        if finalExp < context.minExponent {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: status.union(Decimal.Status.underflow))
        }

        // 9. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func multiply(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try multiply(other, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format64 {
    public func multiply(
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
            if b.test.zero {
                // ∞ × 0 = NaN (invalid)
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }
        if b.test.infinite {
            if a.test.zero {
                // 0 × ∞ = NaN (invalid)
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }

        // 3. Handle zero cases
        if a.test.zero || b.test.zero {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 4. Extract components
        let coeffA = UInt128(a.extractCoefficient())
        let coeffB = UInt128(b.extractCoefficient())
        let expA = a.extractExponent()
        let expB = b.extractExponent()

        // 5. Multiply coefficients and add exponents
        let resultCoeff = coeffA * coeffB
        let resultExp = expA + expB

        // 6. Round to precision
        let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
            coefficient: resultCoeff,
            exponent: resultExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        // 7. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 8. Check for underflow
        if finalExp < context.minExponent {
            // For now, return zero on underflow
            return Decimal.Outcome(value: .zero(sign: resultSign), status: status.union(Decimal.Status.underflow))
        }

        // 9. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func multiply(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try multiply(other, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format128 {
    public func multiply(
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
            if b.test.zero {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }
        if b.test.infinite {
            if a.test.zero {
                return Decimal.Outcome(value: .nan(), status: .invalid)
            }
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: .none)
        }

        // 3. Handle zero cases
        if a.test.zero || b.test.zero {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
        }

        // 4. Extract components
        let coeffA = a.extractCoefficient()
        let coeffB = b.extractCoefficient()
        let expA = a.extractExponent()
        let expB = b.extractExponent()

        // 5. Multiply coefficients and add exponents
        // Note: For full precision we'd need 256-bit arithmetic
        // For now, use simplified approach that works for most cases
        let resultCoeff = coeffA * coeffB
        let resultExp = expA + expB

        // 6. Round to precision
        let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
            coefficient: resultCoeff,
            exponent: resultExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        // 7. Check for overflow
        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        // 8. Check for underflow
        if finalExp < context.minExponent {
            return Decimal.Outcome(value: .zero(sign: resultSign), status: status.union(Decimal.Status.underflow))
        }

        // 9. Encode result
        let result = Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff)
        return Decimal.Outcome(value: result, status: status)
    }

    public func multiply(
        _ other: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try multiply(other, context: context).trapped(by: context.traps)
    }
}
