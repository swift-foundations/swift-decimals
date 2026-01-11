extension Decimal {
    /// IEEE trap carrying the flag, accumulated status, AND the computed value
    public struct Trap<Value>: Error, Hashable where Value: Hashable {
        /// The flag that triggered the trap
        public let flag: Flag

        /// All accumulated status flags
        public let status: Status

        /// The value that would have been returned (IEEE specifies result even on trap)
        public let value: Value

        public init(flag: Flag, status: Status, value: Value) {
            self.flag = flag
            self.status = status
            self.value = value
        }
    }
}

extension Decimal.Trap: Sendable where Value: Sendable { }
