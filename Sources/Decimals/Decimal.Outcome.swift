extension Decimal {
    public struct Outcome<Value> {
        public let value: Value
        public let status: Status

        public init(value: Value, status: Status) {
            self.value = value
            self.status = status
        }
    }
}

extension Decimal.Outcome: Sendable where Value: Sendable { }
extension Decimal.Outcome: Equatable where Value: Equatable { }
extension Decimal.Outcome: Hashable where Value: Hashable { }

extension Decimal.Outcome where Value: Sendable & Hashable {
    /// Throws if any trapped flag is raised; trap carries the value
    public func trapped(by traps: Decimal.Status) throws(Decimal.Trap<Value>) -> Value {
        let raised = status.intersection(traps)
        if !raised.isEmpty {
            for flag in Decimal.Flag.allCases {
                if raised.contains(flag) {
                    throw Decimal.Trap(flag: flag, status: status, value: value)
                }
            }
        }
        return value
    }
}
