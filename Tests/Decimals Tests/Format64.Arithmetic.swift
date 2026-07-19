import Testing

@testable import Decimals

extension Decimal.Format64 {
    @Suite struct Test {

        // MARK: - Addition

        @Test func `addition Basic`() {
            let a: Decimal.Format64 = 10
            let b: Decimal.Format64 = 5
            let result = a + b
            #expect(Int64(exactly: result) == 15)
        }

        @Test func `addition Negative`() {
            let a: Decimal.Format64 = 10
            let b: Decimal.Format64 = -3
            let result = a + b
            #expect(Int64(exactly: result) == 7)
        }

        @Test func `addition Zero`() {
            let a: Decimal.Format64 = 42
            let b: Decimal.Format64 = 0
            let result = a + b
            #expect(Int64(exactly: result) == 42)
        }

        @Test func `addition Infinity`() {
            let a: Decimal.Format64 = 42
            let inf = Decimal.Format64.infinity()
            let result = a + inf
            #expect(result.test.infinite)
        }

        @Test func `addition Opposite Infinity`() {
            let posInf = Decimal.Format64.infinity()
            let negInf = Decimal.Format64.infinity(sign: .negative)
            let result = posInf + negInf
            #expect(result.test.nan)
        }

        // MARK: - Subtraction

        @Test func `subtraction Basic`() {
            let a: Decimal.Format64 = 10
            let b: Decimal.Format64 = 3
            let result = a - b
            #expect(Int64(exactly: result) == 7)
        }

        @Test func `subtraction Negative Result`() {
            let a: Decimal.Format64 = 3
            let b: Decimal.Format64 = 10
            let result = a - b
            #expect(Int64(exactly: result) == -7)
        }

        // MARK: - Multiplication

        @Test func `multiplication Basic`() {
            let a: Decimal.Format64 = 6
            let b: Decimal.Format64 = 7
            let result = a * b
            #expect(Int64(exactly: result) == 42)
        }

        @Test func `multiplication By Zero`() {
            let a: Decimal.Format64 = 42
            let b: Decimal.Format64 = 0
            let result = a * b
            #expect(result.test.zero)
        }

        @Test func `multiplication By Negative`() {
            let a: Decimal.Format64 = 6
            let b: Decimal.Format64 = -7
            let result = a * b
            #expect(Int64(exactly: result) == -42)
        }

        @Test func `multiplication Infinity By Zero`() {
            let inf = Decimal.Format64.infinity()
            let zero: Decimal.Format64 = 0
            let result = inf * zero
            #expect(result.test.nan)
        }

        // MARK: - Division

        @Test func `division Basic`() {
            let a: Decimal.Format64 = 42
            let b: Decimal.Format64 = 6
            let result = a / b
            #expect(Int64(exactly: result) == 7)
        }

        @Test func `division By Zero`() {
            let a: Decimal.Format64 = 42
            let b: Decimal.Format64 = 0
            let result = a / b
            #expect(result.test.infinite)
        }

        @Test func `division Zero By Zero`() {
            let a: Decimal.Format64 = 0
            let b: Decimal.Format64 = 0
            let result = a / b
            #expect(result.test.nan)
        }

        @Test func `division Infinity By Infinity`() {
            let a = Decimal.Format64.infinity()
            let b = Decimal.Format64.infinity()
            let result = a / b
            #expect(result.test.nan)
        }

        // MARK: - Comparison

        @Test func `comparison Less`() {
            let a: Decimal.Format64 = 5
            let b: Decimal.Format64 = 10
            #expect(a < b)
            #expect(!(b < a))
        }

        @Test func `comparison Equal`() {
            let a: Decimal.Format64 = 42
            let b: Decimal.Format64 = 42
            #expect(!(a < b))
            #expect(!(b < a))
        }

        // MARK: - Integer Conversion

        @Test func `integer Conversion`() {
            let a: Decimal.Format64 = 12345
            #expect(Int64(exactly: a) == 12345)
        }

        @Test func `negative Integer Conversion`() {
            let a: Decimal.Format64 = -9876
            #expect(Int64(exactly: a) == -9876)
        }
    }
}

extension Decimal.Format64.Test {
    @Suite struct `Edge Case` {

        // MARK: - Addition

        @Test func `addition does not overflow coefficient scaling at large exponent difference`() {
            // exponent difference of 38 matches the old fixed threshold
            // (`diff.rawValue > 38`) in Add.swift; scaling a ~16-digit coefficient by
            // 10^38 overflows UInt128 partway through the naive multiply loop (F-002).
            let a = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 9_007_199_254_740_991)
            let b = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(-38), coefficient: 1)
            let result = a.operation.add(b)
            #expect(!result.value.test.nan)
        }

        // MARK: - Fuse

        @Test func `fuse does not silently combine unaligned coefficients when exponent difference exceeds old cutoff`() {
            // x*y = 1 at exponent 0; z = 1 at exponent -100. The exponent difference
            // (100) exceeds the old fixed cutoff (`diff.rawValue <= 70`), which used
            // to leave both coefficients unscaled and combine them as if they shared
            // an exponent, yielding 1 + 1 = 2 instead of the correct (product
            // dominates; z is negligible beyond Format64's 16-digit precision) ~1 (F-003).
            let x = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let y = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(-100), coefficient: 1)
            let result = x.operation.fuse(y, z)
            #expect(Int64(exactly: result.value) == 1)
        }
    }
}
