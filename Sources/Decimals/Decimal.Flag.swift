extension Decimal {
    public enum Flag: Sendable, Hashable, CaseIterable {
        case invalid
        case divide
        case overflow
        case underflow
        case inexact
    }
}
