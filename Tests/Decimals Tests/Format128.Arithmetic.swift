import Testing

@testable import Decimals

extension Decimal.Format128.Test {
    @Suite struct `Edge Case` {

        // MARK: - Addition

        @Test func `addition does not overflow coefficient scaling at large exponent difference`() {
            // exponent difference of 70 matches the old fixed threshold
            // (`diff.rawValue > 70`) in Add.swift; scaling coeffA by 10^70 overflows
            // UInt128 partway through the naive multiply loop (F-002).
            let a = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let b = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(-70), coefficient: 1)
            let result = a.operation.add(b)
            #expect(!result.value.test.nan)
        }
    }
}
