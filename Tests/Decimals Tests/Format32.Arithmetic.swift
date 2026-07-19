import Testing

@testable import Decimals

extension Decimal.Format32.Test {
    @Suite struct `Edge Case` {

        // MARK: - Addition

        @Test func `addition does not overflow coefficient scaling at large exponent difference`() {
            // exponent difference of 20 matches the old fixed threshold
            // (`diff.rawValue > 20`) in Add.swift; scaling coeffA by 10^20 overflows
            // UInt64 partway through the naive multiply loop (F-002).
            let a = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let b = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(-20), coefficient: 1)
            let result = a.operation.add(b)
            #expect(!result.value.test.nan)
        }
    }
}
