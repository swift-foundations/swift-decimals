extension Decimal {
    public struct Context: Sendable, Hashable {
        /// Number of significant digits
        public var precision: Precision

        /// Rounding mode
        public var rounding: Rounding

        /// Which flags trigger traps
        public var traps: Status

        /// Exponent clamping behavior
        public var clamp: Clamp

        /// When to detect tininess for underflow
        public var tininess: Tininess

        /// Maximum exponent
        public var maxExponent: Exponent

        /// Minimum exponent
        public var minExponent: Exponent

        public init(
            precision: Precision,
            rounding: Rounding = .even,
            traps: Status = .none,
            clamp: Clamp = .none,
            tininess: Tininess = .after,
            maxExponent: Exponent,
            minExponent: Exponent
        ) {
            self.precision = precision
            self.rounding = rounding
            self.traps = traps
            self.clamp = clamp
            self.tininess = tininess
            self.maxExponent = maxExponent
            self.minExponent = minExponent
        }
    }
}

extension Decimal.Context {
    public static let format32 = Self(
        precision: .format32,
        maxExponent: Decimal.Exponent.Format32.max,
        minExponent: Decimal.Exponent.Format32.min
    )

    public static let format64 = Self(
        precision: .format64,
        maxExponent: Decimal.Exponent.Format64.max,
        minExponent: Decimal.Exponent.Format64.min
    )

    public static let format128 = Self(
        precision: .format128,
        maxExponent: Decimal.Exponent.Format128.max,
        minExponent: Decimal.Exponent.Format128.min
    )
}
