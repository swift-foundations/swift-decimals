// MARK: - Format64 Division & Comparison

extension Decimal.Format64 {
    public static func / (lhs: Self, rhs: Self) -> Self {
        lhs.operation.divide(rhs).value
    }

    public static func /= (lhs: inout Self, rhs: Self) {
        lhs = lhs / rhs
    }
}

extension Decimal.Format64: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.operation.precedes(rhs)
    }
}

// MARK: - Format32 Division & Comparison

extension Decimal.Format32 {
    public static func / (lhs: Self, rhs: Self) -> Self {
        lhs.operation.divide(rhs).value
    }

    public static func /= (lhs: inout Self, rhs: Self) {
        lhs = lhs / rhs
    }
}

extension Decimal.Format32: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.operation.precedes(rhs)
    }
}

// MARK: - Format128 Division & Comparison

extension Decimal.Format128 {
    public static func / (lhs: Self, rhs: Self) -> Self {
        lhs.operation.divide(rhs).value
    }

    public static func /= (lhs: inout Self, rhs: Self) {
        lhs = lhs / rhs
    }
}

extension Decimal.Format128: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.operation.precedes(rhs)
    }
}
