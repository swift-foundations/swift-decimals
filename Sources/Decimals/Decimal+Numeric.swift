// MARK: - Format64 Numeric Conformance

extension Decimal.Format64: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self.init(value)
    }
}

extension Decimal.Format64: AdditiveArithmetic {
    public static var zero: Self { .zero() }

    public static func + (lhs: Self, rhs: Self) -> Self {
        lhs.operation.add(rhs).value
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        lhs.operation.add(rhs.negated).value
    }
}

extension Decimal.Format64: Swift.Numeric {
    public typealias Magnitude = Self

    public var magnitude: Magnitude {
        sign == .negative ? negated : self
    }

    public init?<T: BinaryInteger>(exactly source: T) {
        guard let int64 = Int64(exactly: source) else {
            return nil
        }
        self.init(int64)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        lhs.operation.multiply(rhs).value
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }
}

extension Decimal.Format64: SignedNumeric {
    public mutating func negate() {
        self = negated
    }

    public static prefix func - (value: Self) -> Self {
        value.negated
    }
}

// MARK: - Format32 Numeric Conformance

extension Decimal.Format32: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int32) {
        if value == 0 {
            self = .zero()
            return
        }

        let sign: Decimal.Sign = value < 0 ? .negative : .positive
        let magnitude = value < 0 ? UInt32(bitPattern: -value) : UInt32(value)

        // BID encoding: store coefficient directly
        // Exponent = 0 (biased = 101)
        let biasedExponent: UInt32 = 101
        let signBit: UInt32 = sign == .negative ? 0x8000_0000 : 0

        self.init(bits: signBit | (biasedExponent << 23) | magnitude)
    }
}

extension Decimal.Format32: AdditiveArithmetic {
    public static var zero: Self { .zero() }

    public static func + (lhs: Self, rhs: Self) -> Self {
        lhs.operation.add(rhs).value
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        lhs.operation.add(rhs.negated).value
    }
}

extension Decimal.Format32: Swift.Numeric {
    public typealias Magnitude = Self

    public var magnitude: Magnitude {
        sign == .negative ? negated : self
    }

    public init?<T: BinaryInteger>(exactly source: T) {
        guard let int32 = Int32(exactly: source) else {
            return nil
        }
        self.init(integerLiteral: int32)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        lhs.operation.multiply(rhs).value
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }
}

extension Decimal.Format32: SignedNumeric {
    public mutating func negate() {
        self = negated
    }

    public static prefix func - (value: Self) -> Self {
        value.negated
    }
}

// MARK: - Format128 Numeric Conformance

extension Decimal.Format128: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        if value == 0 {
            self = .zero()
            return
        }

        let sign: Decimal.Sign = value < 0 ? .negative : .positive
        let magnitude = value < 0 ? UInt64(bitPattern: -value) : UInt64(value)

        // BID encoding for 128-bit: coefficient in low word, exponent in high word
        // Exponent = 0 (biased = 6176)
        let biasedExponent: UInt64 = 6176
        let signBit: UInt64 = sign == .negative ? 0x8000_0000_0000_0000 : 0

        self.init(high: signBit | (biasedExponent << 49), low: magnitude)
    }
}

extension Decimal.Format128: AdditiveArithmetic {
    public static var zero: Self { .zero() }

    public static func + (lhs: Self, rhs: Self) -> Self {
        lhs.operation.add(rhs).value
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        lhs.operation.add(rhs.negated).value
    }
}

extension Decimal.Format128: Swift.Numeric {
    public typealias Magnitude = Self

    public var magnitude: Magnitude {
        sign == .negative ? negated : self
    }

    public init?<T: BinaryInteger>(exactly source: T) {
        guard let int64 = Int64(exactly: source) else {
            return nil
        }
        self.init(integerLiteral: int64)
    }

    public static func * (lhs: Self, rhs: Self) -> Self {
        lhs.operation.multiply(rhs).value
    }

    public static func *= (lhs: inout Self, rhs: Self) {
        lhs = lhs * rhs
    }
}

extension Decimal.Format128: SignedNumeric {
    public mutating func negate() {
        self = negated
    }

    public static prefix func - (value: Self) -> Self {
        value.negated
    }
}
