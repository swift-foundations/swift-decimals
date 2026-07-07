extension Decimal.Operation where Value == Decimal.Format32 {
    /// IEEE 754 total ordering (always defined, NaN has defined position)
    public func order(_ other: Value) -> Decimal.Order {
        // IEEE 754 total ordering:
        // -NaN < -Inf < -finite < -0 < +0 < +finite < +Inf < +NaN

        let baseClass = base.classification
        let otherClass = other.classification
        let baseNeg = base.test.negative
        let otherNeg = other.test.negative

        func rank(_ c: Decimal.Class, negative: Bool) -> Int {
            switch c {
            case .quiet: return negative ? 0 : 7
            case .signaling: return negative ? 1 : 6
            case .infinite: return negative ? 2 : 5
            case .normal, .subnormal: return negative ? 3 : 4
            case .zero: return negative ? 3 : 4
            }
        }

        let baseRank = rank(baseClass, negative: baseNeg)
        let otherRank = rank(otherClass, negative: otherNeg)

        if baseRank != otherRank {
            return baseRank < otherRank ? .less : .greater
        }

        // Same rank - compare within category
        if baseClass == .zero && otherClass == .zero {
            if baseNeg && !otherNeg { return .less }
            if !baseNeg && otherNeg { return .greater }
            return .equal
        }

        // For NaNs: compare by signaling status then payload
        if baseClass == .quiet || baseClass == .signaling {
            let basePayload = base.bits & 0x000F_FFFF
            let otherPayload = other.bits & 0x000F_FFFF
            if basePayload == otherPayload { return .equal }
            let payloadOrder: Decimal.Order = basePayload < otherPayload ? .less : .greater
            return baseNeg ? (payloadOrder == .less ? .greater : .less) : payloadOrder
        }

        // For finite numbers, use numerical comparison
        let cmp = compare(other)
        switch cmp {
        case .less: return .less
        case .equal: return .equal
        case .greater: return .greater
        case .unordered: return .equal
        }
    }

    public func precedes(_ other: Value) -> Bool {
        order(other) == .less
    }
}

extension Decimal.Operation where Value == Decimal.Format64 {
    /// IEEE 754 total ordering (always defined, NaN has defined position)
    public func order(_ other: Value) -> Decimal.Order {
        // IEEE 754 total ordering:
        // -NaN < -Inf < -finite < -0 < +0 < +finite < +Inf < +NaN
        // Within NaNs: signaling < quiet, then by payload

        let baseClass = base.classification
        let otherClass = other.classification
        let baseNeg = base.test.negative
        let otherNeg = other.test.negative

        // Get ordering rank for classification
        func rank(_ c: Decimal.Class, negative: Bool) -> Int {
            switch c {
            case .quiet: return negative ? 0 : 7
            case .signaling: return negative ? 1 : 6
            case .infinite: return negative ? 2 : 5
            case .normal, .subnormal: return negative ? 3 : 4
            case .zero: return negative ? 3 : 4  // -0 and +0 treated specially
            }
        }

        let baseRank = rank(baseClass, negative: baseNeg)
        let otherRank = rank(otherClass, negative: otherNeg)

        if baseRank != otherRank {
            return baseRank < otherRank ? .less : .greater
        }

        // Same rank - compare within category
        // For zeros: -0 < +0
        if baseClass == .zero && otherClass == .zero {
            if baseNeg && !otherNeg { return .less }
            if !baseNeg && otherNeg { return .greater }
            return .equal
        }

        // For NaNs: compare by signaling status then payload
        if baseClass == .quiet || baseClass == .signaling {
            let basePayload = base.bits & 0x0000_FFFF_FFFF_FFFF
            let otherPayload = other.bits & 0x0000_FFFF_FFFF_FFFF
            if basePayload == otherPayload { return .equal }
            let payloadOrder: Decimal.Order = basePayload < otherPayload ? .less : .greater
            return baseNeg ? (payloadOrder == .less ? .greater : .less) : payloadOrder
        }

        // For finite numbers, use numerical comparison
        let cmp = compare(other)
        switch cmp {
        case .less: return .less
        case .equal: return .equal
        case .greater: return .greater
        case .unordered: return .equal  // Should not happen for finite numbers
        }
    }

    public func precedes(_ other: Value) -> Bool {
        order(other) == .less
    }
}

extension Decimal.Operation where Value == Decimal.Format128 {
    /// IEEE 754 total ordering (always defined, NaN has defined position)
    public func order(_ other: Value) -> Decimal.Order {
        // IEEE 754 total ordering:
        // -NaN < -Inf < -finite < -0 < +0 < +finite < +Inf < +NaN

        let baseClass = base.classification
        let otherClass = other.classification
        let baseNeg = base.test.negative
        let otherNeg = other.test.negative

        func rank(_ c: Decimal.Class, negative: Bool) -> Int {
            switch c {
            case .quiet: return negative ? 0 : 7
            case .signaling: return negative ? 1 : 6
            case .infinite: return negative ? 2 : 5
            case .normal, .subnormal: return negative ? 3 : 4
            case .zero: return negative ? 3 : 4
            }
        }

        let baseRank = rank(baseClass, negative: baseNeg)
        let otherRank = rank(otherClass, negative: otherNeg)

        if baseRank != otherRank {
            return baseRank < otherRank ? .less : .greater
        }

        // Same rank - compare within category
        if baseClass == .zero && otherClass == .zero {
            if baseNeg && !otherNeg { return .less }
            if !baseNeg && otherNeg { return .greater }
            return .equal
        }

        // For NaNs: compare by payload
        if baseClass == .quiet || baseClass == .signaling {
            // 128-bit NaN payload is in low word
            let basePayload = base.low
            let otherPayload = other.low
            if basePayload == otherPayload { return .equal }
            let payloadOrder: Decimal.Order = basePayload < otherPayload ? .less : .greater
            return baseNeg ? (payloadOrder == .less ? .greater : .less) : payloadOrder
        }

        // For finite numbers, use numerical comparison
        let cmp = compare(other)
        switch cmp {
        case .less: return .less
        case .equal: return .equal
        case .greater: return .greater
        case .unordered: return .equal
        }
    }

    public func precedes(_ other: Value) -> Bool {
        order(other) == .less
    }
}
