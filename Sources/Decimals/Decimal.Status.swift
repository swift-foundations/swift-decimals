extension Decimal {
    public struct Status: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
}

extension Decimal.Status {
    public static let invalid = Self(rawValue: 1 << 0)
    public static let divide = Self(rawValue: 1 << 1)
    public static let overflow = Self(rawValue: 1 << 2)
    public static let underflow = Self(rawValue: 1 << 3)
    public static let inexact = Self(rawValue: 1 << 4)

    public static let none: Self = []
}

extension Decimal.Status {
    public init(_ flag: Decimal.Flag) {
        switch flag {
        case .invalid: self = .invalid
        case .divide: self = .divide
        case .overflow: self = .overflow
        case .underflow: self = .underflow
        case .inexact: self = .inexact
        }
    }

    public func contains(_ flag: Decimal.Flag) -> Bool {
        self.contains(Self(flag))
    }
}
