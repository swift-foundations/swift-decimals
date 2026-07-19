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

        // MARK: - Fuse

        @Test func `fuse does not silently combine unaligned coefficients when exponent difference exceeds old cutoff`() {
            // x*y = 1 at exponent 0; z = 1 at exponent -100. The exponent difference
            // (100) exceeds the old fixed cutoff (`diff.rawValue <= 70`), which used
            // to leave both coefficients unscaled and combine them as if they shared
            // an exponent, yielding 1 + 1 = 2 instead of the correct (product
            // dominates; z is negligible beyond Format128's 34-digit precision) ~1 (F-003).
            let x = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let y = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(-100), coefficient: 1)
            let result = x.operation.fuse(y, z)
            #expect(result.value == Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1))
        }
    }
}
