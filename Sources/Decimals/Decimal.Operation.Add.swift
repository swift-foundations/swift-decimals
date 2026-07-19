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
            let resultSign: Decimal.Sign = (a.sign == .negative && b.sign == .negative) ? .negative : (context.rounding == .floor ? .negative : .positive)
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

        // 5. Align exponents by scaling the operand with the larger exponent up by
        // 10^diff to match the smaller exponent's scale. `diff` can be large (the
        // format's exponent range spans hundreds of decades), so scaling must stop
        // the instant it would overflow the working integer type rather than
        // trusting a fixed decade-count cutoff — the old `diff.rawValue > 20` bound
        // let scaling run past UInt64's ~19-20 digit capacity and trap on legal
        // finite inputs (F-002). Once alignment isn't feasible in the working type,
        // the other operand is too small to affect the correctly-rounded result.
        if expA < expB {
            let diff = expB - expA
            var scaled = coeffB
            var shifted = 0
            while shifted < diff.rawValue {
                let (next, overflow) = scaled.multipliedReportingOverflow(by: 10)
                if overflow { break }
                scaled = next
                shifted += 1
            }
            if shifted < diff.rawValue {
                return Decimal.Outcome(value: b, status: .inexact)
            }
            coeffB = scaled
            expB = expA
        } else if expB < expA {
            let diff = expA - expB
            var scaled = coeffA
            var shifted = 0
            while shifted < diff.rawValue {
                let (next, overflow) = scaled.multipliedReportingOverflow(by: 10)
                if overflow { break }
                scaled = next
                shifted += 1
            }
            if shifted < diff.rawValue {
                return Decimal.Outcome(value: a, status: .inexact)
            }
            coeffA = scaled
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
            let resultSign: Decimal.Sign = (a.sign == .negative && b.sign == .negative) ? .negative : (context.rounding == .floor ? .negative : .positive)
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

        // 5. Align exponents by scaling the operand with the larger exponent up by
        // 10^diff to match the smaller exponent's scale. `diff` can be large (the
        // format's exponent range spans hundreds of decades), so scaling must stop
        // the instant it would overflow the working integer type rather than
        // trusting a fixed decade-count cutoff — the old `diff.rawValue > 38` bound
        // let scaling run past UInt128's ~38-39 digit capacity and trap on legal
        // finite inputs (F-002). Once alignment isn't feasible in the working type,
        // the other operand is too small to affect the correctly-rounded result.
        if expA < expB {
            let diff = expB - expA
            var scaled = coeffB
            var shifted = 0
            while shifted < diff.rawValue {
                let (next, overflow) = scaled.multipliedReportingOverflow(by: 10)
                if overflow { break }
                scaled = next
                shifted += 1
            }
            if shifted < diff.rawValue {
                // B is so much larger that A is negligible
                return Decimal.Outcome(value: b, status: .inexact)
            }
            coeffB = scaled
            expB = expA
        } else if expB < expA {
            let diff = expA - expB
            var scaled = coeffA
            var shifted = 0
            while shifted < diff.rawValue {
                let (next, overflow) = scaled.multipliedReportingOverflow(by: 10)
                if overflow { break }
                scaled = next
                shifted += 1
            }
            if shifted < diff.rawValue {
                // A is so much larger that B is negligible
                return Decimal.Outcome(value: a, status: .inexact)
            }
            coeffA = scaled
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
            let resultSign: Decimal.Sign = (a.sign == .negative && b.sign == .negative) ? .negative : (context.rounding == .floor ? .negative : .positive)
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
        let coeffA = a.extractCoefficient()
        let coeffB = b.extractCoefficient()
        let expA = a.extractExponent()
        let expB = b.extractExponent()

        // 5. Align exponents by scaling the operand with the larger exponent up by
        // 10^diff to match the smaller exponent's scale.
        //
        // Format128's headroom above its own precision (UInt128's ~38-39 digit
        // capacity minus this format's 34-digit precision — only ~4-5 digits) is
        // NOT enough to guarantee the far operand is negligible the instant
        // scaling would overflow UInt128: that let the old fixed-cutoff shortcut
        // fire while the far operand was still within reach of the correctly-
        // rounded result, silently dropping a still-significant operand (F-002
        // revision 1; concrete case: 9999999999999999999999999999999999e0 +
        // 9999999999999999999999999999999999e5, exponent gap 5, used to return
        // the bare larger operand instead of the true ~1.00001e40 sum).
        // Format32/64 add are UNCHANGED and remain sound: their working types
        // (UInt64/UInt128) have headroom far exceeding their own precision
        // (7/16 digits), so overflow there can only happen well past the point
        // established by the same guard-digit argument below.
        //
        // The sound boundary is `precision + 2` guard digits of exponent gap:
        // - Below it, the far operand could still land within `precision` digits
        //   of the near operand's most significant digit, so the exact sum is
        //   computed in 256-bit (`Decimals.Wide`) space and rounded once.
        // - At or beyond it, the near operand already carries at most `precision`
        //   digits of its own (a precondition of being a validly encoded value),
        //   so padding it out to `precision` digits can never reach as far down
        //   as the far operand's magnitude — the far operand cannot change a
        //   single retained or guard digit. The shortcut still routes the near
        //   operand's own (coefficient, exponent) through the rounding kernel
        //   with `sticky: true`, which is a proven no-op on the value itself
        //   (its digit count already fits `precision`) that only contributes the
        //   `.inexact` status the discarded operand earns.
        let window = context.precision.rawValue + 2

        if expA < expB {
            let diff = expB - expA
            if diff.rawValue < window {
                let scaledB = Decimals.Wide.multiplied(Decimals.Wide(coeffB), byPowerOf10: diff.rawValue)
                let wideA = Decimals.Wide(coeffA)
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if signA == signB {
                    resultSign = signA
                    wideSum = wideA.adding(scaledB)
                } else if wideA >= scaledB {
                    resultSign = signA
                    wideSum = wideA.subtracting(scaledB)
                } else {
                    resultSign = signB
                    wideSum = scaledB.subtracting(wideA)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reducedToFitUInt128()
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                    coefficient: reduced,
                    exponent: expA + shift,
                    sign: resultSign,
                    rounding: context.rounding,
                    precision: context.precision,
                    sticky: sticky
                )
                if finalExp > context.maxExponent {
                    return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
                }
                return Decimal.Outcome(value: Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff), status: status)
            }
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                coefficient: coeffB,
                exponent: expB,
                sign: signB,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: signB), status: status.union(Decimal.Status.overflow))
            }
            return Decimal.Outcome(value: Value.encode(sign: signB, exponent: finalExp, coefficient: finalCoeff), status: status)
        } else if expB < expA {
            let diff = expA - expB
            if diff.rawValue < window {
                let scaledA = Decimals.Wide.multiplied(Decimals.Wide(coeffA), byPowerOf10: diff.rawValue)
                let wideB = Decimals.Wide(coeffB)
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if signA == signB {
                    resultSign = signA
                    wideSum = scaledA.adding(wideB)
                } else if scaledA >= wideB {
                    resultSign = signA
                    wideSum = scaledA.subtracting(wideB)
                } else {
                    resultSign = signB
                    wideSum = wideB.subtracting(scaledA)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reducedToFitUInt128()
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                    coefficient: reduced,
                    exponent: expB + shift,
                    sign: resultSign,
                    rounding: context.rounding,
                    precision: context.precision,
                    sticky: sticky
                )
                if finalExp > context.maxExponent {
                    return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
                }
                return Decimal.Outcome(value: Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff), status: status)
            }
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                coefficient: coeffA,
                exponent: expA,
                sign: signA,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: signA), status: status.union(Decimal.Status.overflow))
            }
            return Decimal.Outcome(value: Value.encode(sign: signA, exponent: finalExp, coefficient: finalCoeff), status: status)
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
