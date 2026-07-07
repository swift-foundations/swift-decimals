import Testing

@testable import Decimals

@Suite struct Format64ArithmeticTests {

    // MARK: - Addition

    @Test func additionBasic() {
        let a: Decimal.Format64 = 10
        let b: Decimal.Format64 = 5
        let result = a + b
        #expect(Int64(exactly: result) == 15)
    }

    @Test func additionNegative() {
        let a: Decimal.Format64 = 10
        let b: Decimal.Format64 = -3
        let result = a + b
        #expect(Int64(exactly: result) == 7)
    }

    @Test func additionZero() {
        let a: Decimal.Format64 = 42
        let b: Decimal.Format64 = 0
        let result = a + b
        #expect(Int64(exactly: result) == 42)
    }

    @Test func additionInfinity() {
        let a: Decimal.Format64 = 42
        let inf = Decimal.Format64.infinity()
        let result = a + inf
        #expect(result.test.infinite)
    }

    @Test func additionOppositeInfinity() {
        let posInf = Decimal.Format64.infinity()
        let negInf = Decimal.Format64.infinity(sign: .negative)
        let result = posInf + negInf
        #expect(result.test.nan)
    }

    // MARK: - Subtraction

    @Test func subtractionBasic() {
        let a: Decimal.Format64 = 10
        let b: Decimal.Format64 = 3
        let result = a - b
        #expect(Int64(exactly: result) == 7)
    }

    @Test func subtractionNegativeResult() {
        let a: Decimal.Format64 = 3
        let b: Decimal.Format64 = 10
        let result = a - b
        #expect(Int64(exactly: result) == -7)
    }

    // MARK: - Multiplication

    @Test func multiplicationBasic() {
        let a: Decimal.Format64 = 6
        let b: Decimal.Format64 = 7
        let result = a * b
        #expect(Int64(exactly: result) == 42)
    }

    @Test func multiplicationByZero() {
        let a: Decimal.Format64 = 42
        let b: Decimal.Format64 = 0
        let result = a * b
        #expect(result.test.zero)
    }

    @Test func multiplicationByNegative() {
        let a: Decimal.Format64 = 6
        let b: Decimal.Format64 = -7
        let result = a * b
        #expect(Int64(exactly: result) == -42)
    }

    @Test func multiplicationInfinityByZero() {
        let inf = Decimal.Format64.infinity()
        let zero: Decimal.Format64 = 0
        let result = inf * zero
        #expect(result.test.nan)
    }

    // MARK: - Division

    @Test func divisionBasic() {
        let a: Decimal.Format64 = 42
        let b: Decimal.Format64 = 6
        let result = a / b
        #expect(Int64(exactly: result) == 7)
    }

    @Test func divisionByZero() {
        let a: Decimal.Format64 = 42
        let b: Decimal.Format64 = 0
        let result = a / b
        #expect(result.test.infinite)
    }

    @Test func divisionZeroByZero() {
        let a: Decimal.Format64 = 0
        let b: Decimal.Format64 = 0
        let result = a / b
        #expect(result.test.nan)
    }

    @Test func divisionInfinityByInfinity() {
        let a = Decimal.Format64.infinity()
        let b = Decimal.Format64.infinity()
        let result = a / b
        #expect(result.test.nan)
    }

    // MARK: - Comparison

    @Test func comparisonLess() {
        let a: Decimal.Format64 = 5
        let b: Decimal.Format64 = 10
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test func comparisonEqual() {
        let a: Decimal.Format64 = 42
        let b: Decimal.Format64 = 42
        #expect(!(a < b))
        #expect(!(b < a))
    }

    // MARK: - Integer Conversion

    @Test func integerConversion() {
        let a: Decimal.Format64 = 12345
        #expect(Int64(exactly: a) == 12345)
    }

    @Test func negativeIntegerConversion() {
        let a: Decimal.Format64 = -9876
        #expect(Int64(exactly: a) == -9876)
    }
}
