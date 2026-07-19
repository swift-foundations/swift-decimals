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
        // an exponent, silently producing a wrong result (F-003). The guard-digit
        // argument from add()'s F-002 revision 1 fix generalizes here unchanged:
        // below `precision + 2` digits of gap, compute exactly; at or beyond it,
        // the discarded operand cannot affect a single retained or guard digit of
        // the correctly-rounded result, but must still be folded into the
        // rounding decision as a sticky (nonzero-remainder) contribution.
        let window = context.precision.rawValue + 2

        if pExp < zExp {
            let diff = zExp - pExp
            if diff.rawValue < window {
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
            if diff.rawValue < window {
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
        // an exponent, silently producing a wrong result (F-003). The guard-digit
        // argument from add()'s F-002 revision 1 fix generalizes here unchanged:
        // below `precision + 2` digits of gap, compute exactly; at or beyond it,
        // the discarded operand cannot affect a single retained or guard digit of
        // the correctly-rounded result, but must still be folded into the
        // rounding decision as a sticky (nonzero-remainder) contribution.
        let window = context.precision.rawValue + 2

        if productExp < zExp {
            let diff = zExp - productExp
            if diff.rawValue < window {
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
            if diff.rawValue < window {
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
        // shared an exponent, silently producing a wrong result (F-003). The
        // guard-digit argument from add()'s F-002 revision 1 fix generalizes here
        // unchanged: below `precision + 2` digits of gap, compute exactly; at or
        // beyond it, the discarded operand cannot affect a single retained or
        // guard digit of the correctly-rounded result, but must still be folded
        // into the rounding decision as a sticky (nonzero-remainder) contribution.
        let window = context.precision.rawValue + 2

        if productExp < zExp {
            let diff = zExp - productExp
            if diff.rawValue < window {
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
            if diff.rawValue < window {
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
