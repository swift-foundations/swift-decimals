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
                let resultSign: Decimal.Sign = (productSign == .negative && z.sign == .negative) ? .negative :
                                               (context.rounding == .floor ? .negative : .positive)
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
        var pCoeff = productCoeff
        var pExp = productExp
        var zCoeff = UInt128(z.extractCoefficient())
        var zExp = z.extractExponent()

        // Align exponents
        if pExp < zExp {
            let diff = zExp - pExp
            if diff.rawValue <= 70 {
                for _ in 0..<diff.rawValue {
                    zCoeff *= 10
                }
                zExp = pExp
            }
        } else if zExp < pExp {
            let diff = pExp - zExp
            if diff.rawValue <= 70 {
                for _ in 0..<diff.rawValue {
                    pCoeff *= 10
                }
                pExp = zExp
            }
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
                let resultSign: Decimal.Sign = (productSign == .negative && z.sign == .negative) ? .negative :
                                               (context.rounding == .floor ? .negative : .positive)
                return Decimal.Outcome(value: .zero(sign: resultSign), status: .none)
            }
            return Decimal.Outcome(value: z, status: .none)
        }

        // 5. Compute product with full precision
        let coeffX = UInt64(x.extractCoefficient())
        let coeffY = UInt64(y.extractCoefficient())
        let expX = x.extractExponent()
        let expY = y.extractExponent()

        var productCoeff = coeffX * coeffY
        var productExp = expX + expY

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

        var zCoeff = UInt64(z.extractCoefficient())
        var zExp = z.extractExponent()

        // Align exponents
        if productExp < zExp {
            let diff = zExp - productExp
            if diff.rawValue <= 20 {
                for _ in 0..<diff.rawValue {
                    zCoeff *= 10
                }
                zExp = productExp
            }
        } else if zExp < productExp {
            let diff = productExp - zExp
            if diff.rawValue <= 20 {
                for _ in 0..<diff.rawValue {
                    productCoeff *= 10
                }
                productExp = zExp
            }
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
                let resultSign: Decimal.Sign = (productSign == .negative && z.sign == .negative) ? .negative :
                                               (context.rounding == .floor ? .negative : .positive)
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

        var productCoeff = coeffX * coeffY
        var productExp = expX + expY

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

        var zCoeff = z.extractCoefficient()
        var zExp = z.extractExponent()

        // Align exponents
        if productExp < zExp {
            let diff = zExp - productExp
            if diff.rawValue <= 70 {
                for _ in 0..<diff.rawValue {
                    zCoeff *= 10
                }
                zExp = productExp
            }
        } else if zExp < productExp {
            let diff = productExp - zExp
            if diff.rawValue <= 70 {
                for _ in 0..<diff.rawValue {
                    productCoeff *= 10
                }
                productExp = zExp
            }
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
