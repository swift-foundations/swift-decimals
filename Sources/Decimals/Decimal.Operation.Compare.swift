extension Decimal.Operation where Value == Decimal.Format32 {
    /// Numerical comparison (NaN is unordered)
    public func compare(_ other: Value) -> Decimal.Compare {
        // Handle NaN cases first
        if base.test.nan || other.test.nan {
            return .unordered
        }

        // Handle infinities
        let baseInf = base.test.infinite
        let otherInf = other.test.infinite

        if baseInf && otherInf {
            let baseNeg = base.test.negative
            let otherNeg = other.test.negative
            if baseNeg == otherNeg {
                return .equal
            }
            return baseNeg ? .less : .greater
        }

        if baseInf {
            return base.test.negative ? .less : .greater
        }

        if otherInf {
            return other.test.negative ? .greater : .less
        }

        // Handle zeros
        let baseZero = base.test.zero
        let otherZero = other.test.zero

        if baseZero && otherZero {
            return .equal
        }
        if baseZero {
            return other.test.negative ? .greater : .less
        }
        if otherZero {
            return base.test.negative ? .less : .greater
        }

        // Compare finite non-zero values
        let baseNeg = base.test.negative
        let otherNeg = other.test.negative

        if baseNeg != otherNeg {
            return baseNeg ? .less : .greater
        }

        // Same sign - compare magnitudes
        let magnitudeOrder = compareMagnitude(other)

        // For negative numbers, larger magnitude means smaller value
        if baseNeg {
            switch magnitudeOrder {
            case .less: return .greater
            case .greater: return .less
            case .equal: return .equal
            case .unordered: return .unordered
            }
        }
        return magnitudeOrder
    }

    /// Compare absolute values: |base| vs |other|
    @usableFromInline
    internal func compareMagnitude(_ other: Value) -> Decimal.Compare {
        let aCoef = base.extractCoefficient()
        let bCoef = other.extractCoefficient()
        let aExp = base.extractExponent()
        let bExp = other.extractExponent()

        // Same exponent: compare coefficients directly
        if aExp == bExp {
            if aCoef < bCoef { return .less }
            if aCoef > bCoef { return .greater }
            return .equal
        }

        // Different exponents: scale and compare
        // Compare aCoef × 10^aExp vs bCoef × 10^bExp
        let diff = aExp.rawValue - bExp.rawValue

        // If exponent difference exceeds precision, order is determined
        if diff > 7 { return .greater }
        if diff < -7 { return .less }

        // Scale to common exponent using UInt64 (safe for Format32)
        if diff > 0 {
            // Scale aCoef up by 10^diff
            var scaled = UInt64(aCoef)
            for _ in 0..<diff {
                scaled *= 10
            }
            if scaled > UInt64(bCoef) { return .greater }
            if scaled < UInt64(bCoef) { return .less }
            return .equal
        } else {
            // Scale bCoef up by 10^(-diff)
            var scaled = UInt64(bCoef)
            for _ in 0..<(-diff) {
                scaled *= 10
            }
            if UInt64(aCoef) > scaled { return .greater }
            if UInt64(aCoef) < scaled { return .less }
            return .equal
        }
    }
}

extension Decimal.Operation where Value == Decimal.Format64 {
    /// Numerical comparison (NaN is unordered)
    public func compare(_ other: Value) -> Decimal.Compare {
        // Handle NaN cases first
        if base.test.nan || other.test.nan {
            return .unordered
        }

        // Handle infinities
        let baseInf = base.test.infinite
        let otherInf = other.test.infinite

        if baseInf && otherInf {
            let baseNeg = base.test.negative
            let otherNeg = other.test.negative
            if baseNeg == otherNeg {
                return .equal
            }
            return baseNeg ? .less : .greater
        }

        if baseInf {
            return base.test.negative ? .less : .greater
        }

        if otherInf {
            return other.test.negative ? .greater : .less
        }

        // Handle zeros
        let baseZero = base.test.zero
        let otherZero = other.test.zero

        if baseZero && otherZero {
            return .equal
        }
        if baseZero {
            return other.test.negative ? .greater : .less
        }
        if otherZero {
            return base.test.negative ? .less : .greater
        }

        // Compare finite non-zero values
        let baseNeg = base.test.negative
        let otherNeg = other.test.negative

        if baseNeg != otherNeg {
            return baseNeg ? .less : .greater
        }

        // Same sign - compare magnitudes
        let magnitudeOrder = compareMagnitude(other)

        // For negative numbers, larger magnitude means smaller value
        if baseNeg {
            switch magnitudeOrder {
            case .less: return .greater
            case .greater: return .less
            case .equal: return .equal
            case .unordered: return .unordered
            }
        }
        return magnitudeOrder
    }

    /// Compare absolute values: |base| vs |other|
    @usableFromInline
    internal func compareMagnitude(_ other: Value) -> Decimal.Compare {
        let aCoef = base.extractCoefficient()
        let bCoef = other.extractCoefficient()
        let aExp = base.extractExponent()
        let bExp = other.extractExponent()

        // Same exponent: compare coefficients directly
        if aExp == bExp {
            if aCoef < bCoef { return .less }
            if aCoef > bCoef { return .greater }
            return .equal
        }

        // Different exponents: scale and compare
        let diff = aExp.rawValue - bExp.rawValue

        // If exponent difference exceeds precision, order is determined
        if diff > 16 { return .greater }
        if diff < -16 { return .less }

        // Scale to common exponent using UInt128 (safe for Format64)
        if diff > 0 {
            var scaled = UInt128(aCoef)
            for _ in 0..<diff {
                scaled *= 10
            }
            let bCoef128 = UInt128(bCoef)
            if scaled > bCoef128 { return .greater }
            if scaled < bCoef128 { return .less }
            return .equal
        } else {
            var scaled = UInt128(bCoef)
            for _ in 0..<(-diff) {
                scaled *= 10
            }
            let aCoef128 = UInt128(aCoef)
            if aCoef128 > scaled { return .greater }
            if aCoef128 < scaled { return .less }
            return .equal
        }
    }
}

extension Decimal.Operation where Value == Decimal.Format128 {
    /// Numerical comparison (NaN is unordered)
    public func compare(_ other: Value) -> Decimal.Compare {
        // Handle NaN cases first
        if base.test.nan || other.test.nan {
            return .unordered
        }

        // Handle infinities
        let baseInf = base.test.infinite
        let otherInf = other.test.infinite

        if baseInf && otherInf {
            let baseNeg = base.test.negative
            let otherNeg = other.test.negative
            if baseNeg == otherNeg {
                return .equal
            }
            return baseNeg ? .less : .greater
        }

        if baseInf {
            return base.test.negative ? .less : .greater
        }

        if otherInf {
            return other.test.negative ? .greater : .less
        }

        // Handle zeros
        let baseZero = base.test.zero
        let otherZero = other.test.zero

        if baseZero && otherZero {
            return .equal
        }
        if baseZero {
            return other.test.negative ? .greater : .less
        }
        if otherZero {
            return base.test.negative ? .less : .greater
        }

        // Compare finite non-zero values
        let baseNeg = base.test.negative
        let otherNeg = other.test.negative

        if baseNeg != otherNeg {
            return baseNeg ? .less : .greater
        }

        // Same sign - compare magnitudes
        let magnitudeOrder = compareMagnitude(other)

        // For negative numbers, larger magnitude means smaller value
        if baseNeg {
            switch magnitudeOrder {
            case .less: return .greater
            case .greater: return .less
            case .equal: return .equal
            case .unordered: return .unordered
            }
        }
        return magnitudeOrder
    }

    /// Compare absolute values: |base| vs |other|
    @usableFromInline
    internal func compareMagnitude(_ other: Value) -> Decimal.Compare {
        let aCoef = base.extractCoefficient()
        let bCoef = other.extractCoefficient()
        let aExp = base.extractExponent()
        let bExp = other.extractExponent()

        // Same exponent: compare coefficients directly
        if aExp == bExp {
            if aCoef < bCoef { return .less }
            if aCoef > bCoef { return .greater }
            return .equal
        }

        // Different exponents: scale and compare
        let diff = aExp.rawValue - bExp.rawValue

        // If exponent difference exceeds precision, order is determined
        if diff > 34 { return .greater }
        if diff < -34 { return .less }

        // Scale to common exponent with overflow detection
        if diff > 0 {
            // Scale aCoef up by 10^diff
            var scaled = aCoef
            for _ in 0..<diff {
                let (result, overflow) = scaled.multipliedReportingOverflow(by: 10)
                if overflow {
                    // Overflow means scaled value exceeds UInt128 max, so |a| > |b|
                    return .greater
                }
                scaled = result
            }
            if scaled > bCoef { return .greater }
            if scaled < bCoef { return .less }
            return .equal
        } else {
            // Scale bCoef up by 10^(-diff)
            var scaled = bCoef
            for _ in 0..<(-diff) {
                let (result, overflow) = scaled.multipliedReportingOverflow(by: 10)
                if overflow {
                    // Overflow means scaled value exceeds UInt128 max, so |b| > |a|
                    return .less
                }
                scaled = result
            }
            if aCoef > scaled { return .greater }
            if aCoef < scaled { return .less }
            return .equal
        }
    }
}
