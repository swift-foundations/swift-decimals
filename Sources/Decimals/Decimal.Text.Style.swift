extension Decimal {
    public enum _TextStyle: Sendable, Hashable {
        /// Plain notation without exponent, such as "123.456"
        case plain
        /// Scientific notation, such as "1.23456E+2"
        case scientific
        /// Engineering notation, exponent multiple of 3, such as "123.456E+0"
        case engineering
    }
}

extension Decimal.Text {
    public typealias Style = Decimal._TextStyle
}
