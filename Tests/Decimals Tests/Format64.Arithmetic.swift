import Testing

@testable import Decimals

@Suite struct Format64ArithmeticTests {

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
