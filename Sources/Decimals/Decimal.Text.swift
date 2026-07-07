extension Decimal {
    /// Text accessor for decimal values - provides parsing and rendering operations.
    public struct Text<Value> {
        @usableFromInline
        let base: Value

        @usableFromInline
        internal init(_ base: Value) {
            self.base = base
        }
    }
}

extension Decimal.Text: Sendable where Value: Sendable {}

// MARK: - Parse Type

extension Decimal.Text {
    /// Static parser for creating decimal values from text.
    public struct Parse {
        @usableFromInline
        internal init() {}
    }
}

extension Decimal.Text.Parse: Sendable {}

// MARK: - Format64 Text Accessor

extension Decimal.Format64 {
    /// Access text operations for this decimal value.
    public var text: Decimal.Text<Self> {
        Decimal.Text(self)
    }

    /// Static text parser for Format64.
    public static var text: Decimal.Text<Self>.Parse {
        Decimal.Text<Self>.Parse()
    }
}

// MARK: - Format32 Text Accessor

extension Decimal.Format32 {
    /// Access text operations for this decimal value.
    public var text: Decimal.Text<Self> {
        Decimal.Text(self)
    }

    /// Static text parser for Format32.
    public static var text: Decimal.Text<Self>.Parse {
        Decimal.Text<Self>.Parse()
    }
}

// MARK: - Format128 Text Accessor

extension Decimal.Format128 {
    /// Access text operations for this decimal value.
    public var text: Decimal.Text<Self> {
        Decimal.Text(self)
    }

    /// Static text parser for Format128.
    public static var text: Decimal.Text<Self>.Parse {
        Decimal.Text<Self>.Parse()
    }
}
