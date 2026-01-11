extension Decimal {
    public enum Rounding: Sendable, Hashable, CaseIterable {
        /// Round toward positive infinity
        case ceiling
        /// Round toward negative infinity
        case floor
        /// Round toward zero (truncate)
        case down
        /// Round away from zero
        case up
        /// Round to nearest, ties to even (banker's rounding) - IEEE default
        case even
        /// Round to nearest, ties away from zero
        case away
        /// Round to nearest, ties toward zero
        case toward
    }
}

extension Decimal.Rounding {
    public static var `default`: Self { .even }
}
