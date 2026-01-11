extension Decimal {
    /// When to detect tininess for underflow
    public enum Tininess: Sendable, Hashable {
        /// Detect before rounding
        case before
        /// Detect after rounding (IEEE 754-2008 default for decimal)
        case after
    }
}

extension Decimal.Tininess {
    public static var `default`: Self { .after }
}
