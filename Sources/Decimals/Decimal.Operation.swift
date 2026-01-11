extension Decimal {
    public struct Operation<Value> {
        @usableFromInline
        let base: Value

        @usableFromInline
        internal init(_ base: Value) {
            self.base = base
        }
    }
}

extension Decimal.Operation: Sendable where Value: Sendable { }

extension Decimal.Format32 {
    public var operation: Decimal.Operation<Self> {
        Decimal.Operation(self)
    }
}

extension Decimal.Format64 {
    public var operation: Decimal.Operation<Self> {
        Decimal.Operation(self)
    }
}

extension Decimal.Format128 {
    public var operation: Decimal.Operation<Self> {
        Decimal.Operation(self)
    }
}
