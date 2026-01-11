extension Decimal {
    public enum Clamp: Sendable, Hashable {
        /// Do not clamp; allow full exponent range
        case none
        /// Clamp exponents to preferred range (IEEE preferred)
        case preferred
    }
}

extension Decimal.Clamp {
    public static var `default`: Self { .none }
}
