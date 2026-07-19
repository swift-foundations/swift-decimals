extension Decimal.Operation where Value == Decimal.Format64 {
    /// Fused multiply-add: (self * a) + b with single rounding
    public func fuse(
        _ a: Value,
        _ b: Value,
        context: Decimal.Context = .format64
    ) -> Decimal.Outcome<Value> {
        let x = base
        let y = a
        let z = b

        // 1. Handle NaN propagation
        if x.test.signaling || y.test.signaling || z.test.signaling {
            let payload: Decimal.Payload
            if x.test.signaling {
                payload = Decimal.Payload(x.extractCoefficient())
            } else if y.test.signaling {
                payload = Decimal.Payload(y.extractCoefficient())
            } else {
                payload = Decimal.Payload(z.extractCoefficient())
            }
            return Decimal.Outcome(value: .nan(kind: .quiet, payload: payload), status: .invalid)
        }

        if x.test.nan { return Decimal.Outcome(value: x, status: .none) }
        if y.test.nan { return Decimal.Outcome(value: y, status: .none) }
        if z.test.nan { return Decimal.Outcome(value: z, status: .none) }

        // 2. Handle infinity * 0 cases
        if (x.test.infinite && y.test.zero) || (x.test.zero && y.test.infinite) {
            return Decimal.Outcome(value: .nan(), status: .invalid)
        }

        // 3. Handle infinity cases
        let productSign: Decimal.Sign = (x.sign == y.sign) ? .positive : .negative

        if x.test.infinite || y.test.infinite {
            if z.test.infinite {
                // ∞ + ∞ of opposite signs = NaN
                if productSign != z.sign {
                    return Decimal.Outcome(value: .nan(), status: .invalid)
                }
            }
            return Decimal.Outcome(value: .infinity(sign: productSign), status: .none)
        }

        if z.test.infinite {
            return Decimal.Outcome(value: z, status: .none)
        }

        // 4. Handle zero cases
        if x.test.zero || y.test.zero {
            if z.test.zero {
                let resultSign: Decimal.Sign = (productSign == .negative && z.sign == .negative) ? .negative : (context.rounding == .floor ? .negative : .positive)
                return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
            }
            return Decimal.Outcome(value: z, status: .none)
        }

        // 5. Compute product with full precision (no intermediate rounding)
        let coeffX = UInt128(x.extractCoefficient())
        let coeffY = UInt128(y.extractCoefficient())
        let expX = x.extractExponent()
        let expY = y.extractExponent()

        let productCoeff = coeffX * coeffY
        let productExp = expX + expY

        // 6. Add z to the product
        if z.test.zero {
            // Just round the product
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                coefficient: productCoeff,
                exponent: productExp,
                sign: productSign,
                rounding: context.rounding,
                precision: context.precision
            )

            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: productSign), status: status.union(Decimal.Status.overflow))
            }

            return Decimal.Outcome(value: Value.encode(sign: productSign, exponent: finalExp, coefficient: finalCoeff), status: status)
        }

        // Need to add z - align exponents and add
        let pCoeff = productCoeff
        let pExp = productExp
        let zCoeff = UInt128(z.extractCoefficient())
        let zExp = z.extractExponent()

        // Align exponents by scaling the operand with the larger exponent up by
        // 10^diff, computing the sum exactly in 256-bit (`Decimals.Wide`) space
        // whenever the gap is small enough that z could still land within
        // `precision` digits of the product's most significant digit.
        //
        // The product coefficient here is UNROUNDED and can already carry up to
        // twice the format's own digit count; scaling either operand further by
        // 10^diff can still exceed UInt128's ~38-39 digit capacity well within the
        // window where the discarded operand is still significant. The old code
        // either fell back to "return the other operand unscaled" the instant
        // scaling overflowed, or — worse — left BOTH coefficients unscaled once
        // `diff` exceeded a fixed cutoff and still combined them as if they shared
        // an exponent, silently producing a wrong result (F-003).
        //
        // Revision 2 (digit-position-aware decision): a FIXED `precision + 2`
        // guard-digit window is unsound — it silently assumes the near
        // (retained) operand carries close to `precision` digits of its own,
        // which is false whenever it has few digits (e.g. `x * y` with both
        // 1-digit inputs). The corrected test: the drop is safe only when the
        // far operand's most significant digit lies strictly more than
        // `precision` digits below the near operand's most significant digit,
        // i.e. `diff > digits(far) - digits(near) + precision`. Below that
        // (inclusive), compute the exact sum in `Decimals.Wide`. `digits(...)`
        // is computed per branch below via `Decimals.Rounding.digitCount` (the
        // near/far roles swap with which operand carries the larger exponent).
        //
        // Overflow safety: the exact branch scales the near operand up by
        // `10^diff`, bounding its scaled span at `digits(near) + diff <=
        // precision + digits(far)`. `z` is a validly encoded Format64 value
        // (`digits(z) <= 16`); the unrounded product can carry up to `2 *
        // precision` (32) digits. Worst case span `16 + 32 = 48` digits,
        // comfortably inside `Decimals.Wide`'s ~77-digit capacity — so
        // `multipliedBy10()`'s precondition is never fed an overflowing scale
        // by a legal finite input. The drop path's `sticky: true` is
        // unconditionally correct: it is only reached once the discarded
        // operand is provably nonzero (zero cases are handled in steps 4/6
        // above).

        if pExp < zExp {
            let diff = zExp - pExp
            let digitsFar = Decimals.Rounding.digitCount(pCoeff)
            let digitsNear = Decimals.Rounding.digitCount(zCoeff)
            let threshold = context.precision.rawValue + digitsFar - digitsNear
            if diff.rawValue <= threshold {
                let scaledZ = Decimals.Wide.multiplied(Decimals.Wide(zCoeff), byPowerOf10: diff.rawValue)
                let wideP = Decimals.Wide(pCoeff)
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if productSign == z.sign {
                    resultSign = productSign
                    wideSum = wideP.adding(scaledZ)
                } else if wideP >= scaledZ {
                    resultSign = productSign
                    wideSum = wideP.subtracting(scaledZ)
                } else {
                    resultSign = z.sign
                    wideSum = scaledZ.subtracting(wideP)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reducedToFitUInt128()
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                    coefficient: reduced,
                    exponent: pExp + shift,
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
            // z dominates the product beyond the guard-digit window; the product
            // is discarded but folded into z's own rounding decision as sticky.
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                coefficient: zCoeff,
                exponent: zExp,
                sign: z.sign,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: z.sign), status: status.union(Decimal.Status.overflow))
            }
            return Decimal.Outcome(value: Value.encode(sign: z.sign, exponent: finalExp, coefficient: finalCoeff), status: status)
        } else if zExp < pExp {
            let diff = pExp - zExp
            let digitsFar = Decimals.Rounding.digitCount(zCoeff)
            let digitsNear = Decimals.Rounding.digitCount(pCoeff)
            let threshold = context.precision.rawValue + digitsFar - digitsNear
            if diff.rawValue <= threshold {
                let scaledP = Decimals.Wide.multiplied(Decimals.Wide(pCoeff), byPowerOf10: diff.rawValue)
                let wideZ = Decimals.Wide(zCoeff)
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if productSign == z.sign {
                    resultSign = productSign
                    wideSum = scaledP.adding(wideZ)
                } else if scaledP >= wideZ {
                    resultSign = productSign
                    wideSum = scaledP.subtracting(wideZ)
                } else {
                    resultSign = z.sign
                    wideSum = wideZ.subtracting(scaledP)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reducedToFitUInt128()
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                    coefficient: reduced,
                    exponent: zExp + shift,
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
            // The product dominates z beyond the guard-digit window; round the
            // (still full-precision, unrounded) product alone, folding the
            // discarded z into the rounding decision as sticky.
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                coefficient: productCoeff,
                exponent: productExp,
                sign: productSign,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: productSign), status: status.union(Decimal.Status.overflow).union(.inexact))
            }
            return Decimal.Outcome(value: Value.encode(sign: productSign, exponent: finalExp, coefficient: finalCoeff), status: status.union(.inexact))
        }

        // Add/subtract based on signs
        let resultSign: Decimal.Sign
        let resultCoeff: UInt128

        if productSign == z.sign {
            resultSign = productSign
            resultCoeff = pCoeff + zCoeff
        } else {
            if pCoeff >= zCoeff {
                resultSign = productSign
                resultCoeff = pCoeff - zCoeff
            } else {
                resultSign = z.sign
                resultCoeff = zCoeff - pCoeff
            }
        }

        if resultCoeff == 0 {
            let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
            return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
        }

        // 7. Round once at the end
        let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
            coefficient: resultCoeff,
            exponent: pExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        return Decimal.Outcome(value: Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff), status: status)
    }

    public func fuse(
        _ a: Value,
        _ b: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try fuse(a, b, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format32 {
    /// Fused multiply-add: (self * a) + b with single rounding
    public func fuse(
        _ a: Value,
        _ b: Value,
        context: Decimal.Context = .format32
    ) -> Decimal.Outcome<Value> {
        let x = base
        let y = a
        let z = b

        // 1. Handle NaN propagation
        if x.test.signaling || y.test.signaling || z.test.signaling {
            let payload: Decimal.Payload
            if x.test.signaling {
                payload = Decimal.Payload(UInt64(x.extractCoefficient()))
            } else if y.test.signaling {
                payload = Decimal.Payload(UInt64(y.extractCoefficient()))
            } else {
                payload = Decimal.Payload(UInt64(z.extractCoefficient()))
            }
            return Decimal.Outcome(value: .nan(kind: .quiet, payload: payload), status: .invalid)
        }

        if x.test.nan { return Decimal.Outcome(value: x, status: .none) }
        if y.test.nan { return Decimal.Outcome(value: y, status: .none) }
        if z.test.nan { return Decimal.Outcome(value: z, status: .none) }

        // 2. Handle infinity * 0 cases
        if (x.test.infinite && y.test.zero) || (x.test.zero && y.test.infinite) {
            return Decimal.Outcome(value: .nan(), status: .invalid)
        }

        // 3. Handle infinity cases
        let productSign: Decimal.Sign = (x.sign == y.sign) ? .positive : .negative

        if x.test.infinite || y.test.infinite {
            if z.test.infinite {
                if productSign != z.sign {
                    return Decimal.Outcome(value: .nan(), status: .invalid)
                }
            }
            return Decimal.Outcome(value: .infinity(sign: productSign), status: .none)
        }

        if z.test.infinite {
            return Decimal.Outcome(value: z, status: .none)
        }

        // 4. Handle zero cases
        if x.test.zero || y.test.zero {
            if z.test.zero {
                let resultSign: Decimal.Sign = (productSign == .negative && z.sign == .negative) ? .negative : (context.rounding == .floor ? .negative : .positive)
                return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
            }
            return Decimal.Outcome(value: z, status: .none)
        }

        // 5. Compute product with full precision
        let coeffX = UInt64(x.extractCoefficient())
        let coeffY = UInt64(y.extractCoefficient())
        let expX = x.extractExponent()
        let expY = y.extractExponent()

        let productCoeff = coeffX * coeffY
        let productExp = expX + expY

        // 6. Add z to the product
        if z.test.zero {
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                coefficient: productCoeff,
                exponent: productExp,
                sign: productSign,
                rounding: context.rounding,
                precision: context.precision
            )

            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: productSign), status: status.union(Decimal.Status.overflow))
            }

            return Decimal.Outcome(value: Value.encode(sign: productSign, exponent: finalExp, coefficient: finalCoeff), status: status)
        }

        let zCoeff = UInt64(z.extractCoefficient())
        let zExp = z.extractExponent()

        // Align exponents by scaling the operand with the larger exponent up by
        // 10^diff, computing the sum exactly in 256-bit (`Decimals.Wide`) space
        // whenever the gap is small enough that z could still land within
        // `precision` digits of the product's most significant digit.
        //
        // The product coefficient here is UNROUNDED and can already carry up to
        // twice the format's own digit count; scaling either operand further by
        // 10^diff can still exceed UInt64's ~19-20 digit capacity well within the
        // window where the discarded operand is still significant. The old code
        // either fell back to "return the other operand unscaled" the instant
        // scaling overflowed, or — worse — left BOTH coefficients unscaled once
        // `diff` exceeded a fixed cutoff and still combined them as if they shared
        // an exponent, silently producing a wrong result (F-003).
        //
        // Revision 2 (digit-position-aware decision): a FIXED `precision + 2`
        // guard-digit window is unsound — it silently assumes the near
        // (retained) operand carries close to `precision` digits of its own,
        // which is false whenever it has few digits (e.g. `x * y` with both
        // 1-digit inputs). The corrected test: the drop is safe only when the
        // far operand's most significant digit lies strictly more than
        // `precision` digits below the near operand's most significant digit,
        // i.e. `diff > digits(far) - digits(near) + precision`. Below that
        // (inclusive), compute the exact sum in `Decimals.Wide`. `digits(...)`
        // is computed per branch below via `Decimals.Rounding.digitCount` (the
        // near/far roles swap with which operand carries the larger exponent).
        //
        // Overflow safety: the exact branch scales the near operand up by
        // `10^diff`, bounding its scaled span at `digits(near) + diff <=
        // precision + digits(far)`. `z` is a validly encoded Format32 value
        // (`digits(z) <= 7`); the unrounded product can carry up to `2 *
        // precision` (14) digits. Worst case span `7 + 14 = 21` digits,
        // comfortably inside `Decimals.Wide`'s ~77-digit capacity — so
        // `multipliedBy10()`'s precondition is never fed an overflowing scale
        // by a legal finite input. The drop path's `sticky: true` is
        // unconditionally correct: it is only reached once the discarded
        // operand is provably nonzero (zero cases are handled in steps 4/6
        // above).

        if productExp < zExp {
            let diff = zExp - productExp
            let digitsFar = Decimals.Rounding.digitCount(productCoeff)
            let digitsNear = Decimals.Rounding.digitCount(zCoeff)
            let threshold = context.precision.rawValue + digitsFar - digitsNear
            if diff.rawValue <= threshold {
                let scaledZ = Decimals.Wide.multiplied(Decimals.Wide(UInt128(zCoeff)), byPowerOf10: diff.rawValue)
                let wideP = Decimals.Wide(UInt128(productCoeff))
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if productSign == z.sign {
                    resultSign = productSign
                    wideSum = wideP.adding(scaledZ)
                } else if wideP >= scaledZ {
                    resultSign = productSign
                    wideSum = wideP.subtracting(scaledZ)
                } else {
                    resultSign = z.sign
                    wideSum = scaledZ.subtracting(wideP)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reduced(toFitBelowOrEqual: UInt128(UInt64.max))
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                    coefficient: UInt64(reduced),
                    exponent: productExp + shift,
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
            // z dominates the product beyond the guard-digit window; the product
            // is discarded but folded into z's own rounding decision as sticky.
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                coefficient: zCoeff,
                exponent: zExp,
                sign: z.sign,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: z.sign), status: status.union(Decimal.Status.overflow))
            }
            return Decimal.Outcome(value: Value.encode(sign: z.sign, exponent: finalExp, coefficient: finalCoeff), status: status)
        } else if zExp < productExp {
            let diff = productExp - zExp
            let digitsFar = Decimals.Rounding.digitCount(zCoeff)
            let digitsNear = Decimals.Rounding.digitCount(productCoeff)
            let threshold = context.precision.rawValue + digitsFar - digitsNear
            if diff.rawValue <= threshold {
                let scaledP = Decimals.Wide.multiplied(Decimals.Wide(UInt128(productCoeff)), byPowerOf10: diff.rawValue)
                let wideZ = Decimals.Wide(UInt128(zCoeff))
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if productSign == z.sign {
                    resultSign = productSign
                    wideSum = scaledP.adding(wideZ)
                } else if scaledP >= wideZ {
                    resultSign = productSign
                    wideSum = scaledP.subtracting(wideZ)
                } else {
                    resultSign = z.sign
                    wideSum = wideZ.subtracting(scaledP)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reduced(toFitBelowOrEqual: UInt128(UInt64.max))
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                    coefficient: UInt64(reduced),
                    exponent: zExp + shift,
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
            // The product dominates z beyond the guard-digit window; round the
            // (still full-precision, unrounded) product alone, folding the
            // discarded z into the rounding decision as sticky.
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
                coefficient: productCoeff,
                exponent: productExp,
                sign: productSign,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: productSign), status: status.union(Decimal.Status.overflow).union(.inexact))
            }
            return Decimal.Outcome(value: Value.encode(sign: productSign, exponent: finalExp, coefficient: finalCoeff), status: status.union(.inexact))
        }

        let resultSign: Decimal.Sign
        let resultCoeff: UInt64

        if productSign == z.sign {
            resultSign = productSign
            resultCoeff = productCoeff + zCoeff
        } else {
            if productCoeff >= zCoeff {
                resultSign = productSign
                resultCoeff = productCoeff - zCoeff
            } else {
                resultSign = z.sign
                resultCoeff = zCoeff - productCoeff
            }
        }

        if resultCoeff == 0 {
            let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
            return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
        }

        let (finalCoeff, finalExp, status) = Decimals.Rounding.round(
            coefficient: resultCoeff,
            exponent: productExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        return Decimal.Outcome(value: Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff), status: status)
    }

    public func fuse(
        _ a: Value,
        _ b: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try fuse(a, b, context: context).trapped(by: context.traps)
    }
}

extension Decimal.Operation where Value == Decimal.Format128 {
    /// Fused multiply-add: (self * a) + b with single rounding
    public func fuse(
        _ a: Value,
        _ b: Value,
        context: Decimal.Context = .format128
    ) -> Decimal.Outcome<Value> {
        let x = base
        let y = a
        let z = b

        // 1. Handle NaN propagation
        if x.test.signaling || y.test.signaling || z.test.signaling {
            let payload: Decimal.Payload
            if x.test.signaling {
                payload = Decimal.Payload(UInt64(truncatingIfNeeded: x.extractCoefficient()))
            } else if y.test.signaling {
                payload = Decimal.Payload(UInt64(truncatingIfNeeded: y.extractCoefficient()))
            } else {
                payload = Decimal.Payload(UInt64(truncatingIfNeeded: z.extractCoefficient()))
            }
            return Decimal.Outcome(value: .nan(kind: .quiet, payload: payload), status: .invalid)
        }

        if x.test.nan { return Decimal.Outcome(value: x, status: .none) }
        if y.test.nan { return Decimal.Outcome(value: y, status: .none) }
        if z.test.nan { return Decimal.Outcome(value: z, status: .none) }

        // 2. Handle infinity * 0 cases
        if (x.test.infinite && y.test.zero) || (x.test.zero && y.test.infinite) {
            return Decimal.Outcome(value: .nan(), status: .invalid)
        }

        // 3. Handle infinity cases
        let productSign: Decimal.Sign = (x.sign == y.sign) ? .positive : .negative

        if x.test.infinite || y.test.infinite {
            if z.test.infinite {
                if productSign != z.sign {
                    return Decimal.Outcome(value: .nan(), status: .invalid)
                }
            }
            return Decimal.Outcome(value: .infinity(sign: productSign), status: .none)
        }

        if z.test.infinite {
            return Decimal.Outcome(value: z, status: .none)
        }

        // 4. Handle zero cases
        if x.test.zero || y.test.zero {
            if z.test.zero {
                let resultSign: Decimal.Sign = (productSign == .negative && z.sign == .negative) ? .negative : (context.rounding == .floor ? .negative : .positive)
                return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
            }
            return Decimal.Outcome(value: z, status: .none)
        }

        // 5. Compute product with full precision
        // Note: For truly full precision FMA with 128-bit decimals, we'd need 256-bit arithmetic
        // This implementation uses UInt128 which may lose precision for very large coefficients
        let coeffX = x.extractCoefficient()
        let coeffY = y.extractCoefficient()
        let expX = x.extractExponent()
        let expY = y.extractExponent()

        let productCoeff = coeffX * coeffY
        let productExp = expX + expY

        // 6. Add z to the product
        if z.test.zero {
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                coefficient: productCoeff,
                exponent: productExp,
                sign: productSign,
                rounding: context.rounding,
                precision: context.precision
            )

            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: productSign), status: status.union(Decimal.Status.overflow))
            }

            return Decimal.Outcome(value: Value.encode(sign: productSign, exponent: finalExp, coefficient: finalCoeff), status: status)
        }

        let zCoeff = z.extractCoefficient()
        let zExp = z.extractExponent()

        // Align exponents by scaling the operand with the larger exponent up by
        // 10^diff, computing the sum exactly in 256-bit (`Decimals.Wide`) space
        // whenever the gap is small enough that z could still land within
        // `precision` digits of the product's most significant digit.
        //
        // Format128's headroom above its own precision (UInt128's ~38-39 digit
        // capacity minus this format's 34-digit precision — only ~4-5 digits) is
        // NOT enough to guarantee the discarded operand is negligible the instant
        // scaling would overflow UInt128 — the same F-002 revision 1 argument
        // that applies to Format128 add() applies here too, and is strictly worse
        // for fuse because the product coefficient is itself already unrounded
        // and can carry up to twice the format's own digit count. The old code
        // either fell back to "return the other operand unscaled" the instant
        // scaling overflowed, or — worse — left BOTH coefficients unscaled once
        // `diff` exceeded a fixed cutoff and still combined them as if they
        // shared an exponent, silently producing a wrong result (F-003).
        //
        // Revision 2 (digit-position-aware decision): a FIXED `precision + 2`
        // guard-digit window is unsound — it silently assumes the near
        // (retained) operand carries close to `precision` digits of its own,
        // which is false whenever it has few digits (e.g. `x * y` with both
        // 1-digit inputs, or `z` alone carrying just 1 digit). The corrected
        // test: the drop is safe only when the far operand's most significant
        // digit lies strictly more than `precision` digits below the near
        // operand's most significant digit, i.e. `diff > digits(far) -
        // digits(near) + precision`. Below that (inclusive), compute the exact
        // sum in `Decimals.Wide`. `digits(...)` is computed per branch below
        // via `Decimals.Rounding.digitCount` (the near/far roles swap with
        // which operand carries the larger exponent).
        //
        // Overflow safety: the exact branch scales the near operand up by
        // `10^diff`, bounding its scaled span at `digits(near) + diff <=
        // precision + digits(far)`. `z` is a validly encoded Format128 value
        // (`digits(z) <= 34`); `productCoeff` is a `UInt128`, so its own
        // checked multiplication (`coeffX * coeffY`, step 5 above) already
        // traps before this code runs on any input whose true product would
        // need more than UInt128's ~39-digit capacity — a pre-existing, out-
        // of-scope limitation, not something this revision changes, but it
        // does mean `digits(product) <= 39` for every input that reaches this
        // alignment logic. Worst case span (`z` dominant, product discarded)
        // `34 + 39 = 73` digits; the opposite case (product dominant, `z`
        // discarded) is bounded by `34 + 34 = 68`. Both are comfortably
        // inside `Decimals.Wide`'s ~77-digit (256-bit) capacity — so
        // `multipliedBy10()`'s precondition is never fed an overflowing scale
        // by a legal finite input. The drop path's `sticky: true` is
        // unconditionally correct: it is only reached once the discarded
        // operand is provably nonzero (zero cases are handled in steps 4/6
        // above).

        if productExp < zExp {
            let diff = zExp - productExp
            let digitsFar = Decimals.Rounding.digitCount(productCoeff)
            let digitsNear = Decimals.Rounding.digitCount(zCoeff)
            let threshold = context.precision.rawValue + digitsFar - digitsNear
            if diff.rawValue <= threshold {
                let scaledZ = Decimals.Wide.multiplied(Decimals.Wide(zCoeff), byPowerOf10: diff.rawValue)
                let wideP = Decimals.Wide(productCoeff)
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if productSign == z.sign {
                    resultSign = productSign
                    wideSum = wideP.adding(scaledZ)
                } else if wideP >= scaledZ {
                    resultSign = productSign
                    wideSum = wideP.subtracting(scaledZ)
                } else {
                    resultSign = z.sign
                    wideSum = scaledZ.subtracting(wideP)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reducedToFitUInt128()
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                    coefficient: reduced,
                    exponent: productExp + shift,
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
            // z dominates the product beyond the guard-digit window; the product
            // is discarded but folded into z's own rounding decision as sticky.
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                coefficient: zCoeff,
                exponent: zExp,
                sign: z.sign,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: z.sign), status: status.union(Decimal.Status.overflow))
            }
            return Decimal.Outcome(value: Value.encode(sign: z.sign, exponent: finalExp, coefficient: finalCoeff), status: status)
        } else if zExp < productExp {
            let diff = productExp - zExp
            let digitsFar = Decimals.Rounding.digitCount(zCoeff)
            let digitsNear = Decimals.Rounding.digitCount(productCoeff)
            let threshold = context.precision.rawValue + digitsFar - digitsNear
            if diff.rawValue <= threshold {
                let scaledP = Decimals.Wide.multiplied(Decimals.Wide(productCoeff), byPowerOf10: diff.rawValue)
                let wideZ = Decimals.Wide(zCoeff)
                let resultSign: Decimal.Sign
                let wideSum: Decimals.Wide
                if productSign == z.sign {
                    resultSign = productSign
                    wideSum = scaledP.adding(wideZ)
                } else if scaledP >= wideZ {
                    resultSign = productSign
                    wideSum = scaledP.subtracting(wideZ)
                } else {
                    resultSign = z.sign
                    wideSum = wideZ.subtracting(scaledP)
                }
                if wideSum.isZero {
                    let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
                    return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
                }
                let (reduced, shift, sticky) = wideSum.reducedToFitUInt128()
                let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                    coefficient: reduced,
                    exponent: zExp + shift,
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
            // The product dominates z beyond the guard-digit window; round the
            // (still full-precision, unrounded) product alone, folding the
            // discarded z into the rounding decision as sticky.
            let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
                coefficient: productCoeff,
                exponent: productExp,
                sign: productSign,
                rounding: context.rounding,
                precision: context.precision,
                sticky: true
            )
            if finalExp > context.maxExponent {
                return Decimal.Outcome(value: .infinity(sign: productSign), status: status.union(Decimal.Status.overflow).union(.inexact))
            }
            return Decimal.Outcome(value: Value.encode(sign: productSign, exponent: finalExp, coefficient: finalCoeff), status: status.union(.inexact))
        }

        let resultSign: Decimal.Sign
        let resultCoeff: UInt128

        if productSign == z.sign {
            resultSign = productSign
            resultCoeff = productCoeff + zCoeff
        } else {
            if productCoeff >= zCoeff {
                resultSign = productSign
                resultCoeff = productCoeff - zCoeff
            } else {
                resultSign = z.sign
                resultCoeff = zCoeff - productCoeff
            }
        }

        if resultCoeff == 0 {
            let zeroSign: Decimal.Sign = context.rounding == .floor ? .negative : .positive
            return Decimal.Outcome(value: .zero(sign: zeroSign), status: .none)
        }

        let (finalCoeff, finalExp, status) = Decimals.Rounding.round128(
            coefficient: resultCoeff,
            exponent: productExp,
            sign: resultSign,
            rounding: context.rounding,
            precision: context.precision
        )

        if finalExp > context.maxExponent {
            return Decimal.Outcome(value: .infinity(sign: resultSign), status: status.union(Decimal.Status.overflow))
        }

        return Decimal.Outcome(value: Value.encode(sign: resultSign, exponent: finalExp, coefficient: finalCoeff), status: status)
    }

    public func fuse(
        _ a: Value,
        _ b: Value,
        trapping context: Decimal.Context
    ) throws(Decimal.Trap<Value>) -> Value {
        try fuse(a, b, context: context).trapped(by: context.traps)
    }
}
