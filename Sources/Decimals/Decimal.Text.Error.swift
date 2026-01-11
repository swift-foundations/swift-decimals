extension Decimal {
    public enum _TextError: Swift.Error, Sendable, Hashable {
        /// Input was empty
        case empty
        /// Invalid syntax at byte offset
        case syntax(offset: Int)
        /// Exponent too high
        case high
        /// Exponent too low
        case low
    }
}

extension Decimal.Text {
    public typealias Error = Decimal._TextError
}
