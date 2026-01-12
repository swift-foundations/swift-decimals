import Testing
@testable import Decimals

@Suite struct Format64TextTests {

    // MARK: - Parsing

    @Test func parseInteger() throws {
        let value = try Decimal.Format64.text([UInt8]("123".utf8))
        #expect(Int64(exactly: value) == 123)
    }

    @Test func parseNegativeInteger() throws {
        let value = try Decimal.Format64.text([UInt8]("-456".utf8))
        #expect(Int64(exactly: value) == -456)
    }

    @Test func parseDecimal() throws {
        let value = try Decimal.Format64.text([UInt8]("12.5".utf8))
        // 12.5 = 125 * 10^-1
        let doubled = value + value  // 25
        #expect(Int64(exactly: doubled) == 25)
    }

    @Test func parseScientific() throws {
        let value = try Decimal.Format64.text([UInt8]("1.5E2".utf8))
        #expect(Int64(exactly: value) == 150)
    }

    @Test func parseInfinity() throws {
        let inf = try Decimal.Format64.text([UInt8]("Infinity".utf8))
        #expect(inf.test.infinite)
        #expect(!inf.test.negative)
    }

    @Test func parseNegativeInfinity() throws {
        let negInf = try Decimal.Format64.text([UInt8]("-Inf".utf8))
        #expect(negInf.test.infinite)
        #expect(negInf.test.negative)
    }

    @Test func parseNaN() throws {
        let nan = try Decimal.Format64.text([UInt8]("NaN".utf8))
        #expect(nan.test.nan)
    }

    @Test func parseZero() throws {
        let zero = try Decimal.Format64.text([UInt8]("0".utf8))
        #expect(zero.test.zero)
    }

    @Test func parseEmpty() {
        #expect(throws: Decimal._TextError.self) {
            _ = try Decimal.Format64.text([UInt8]())
        }
    }

    // MARK: - Rendering

    @Test func renderInteger() {
        let value: Decimal.Format64 = 42
        var buffer: [UInt8] = []
        value.text.render(appending: &buffer)
        #expect(String(decoding: buffer, as: UTF8.self) == "42")
    }

    @Test func renderNegative() {
        let value: Decimal.Format64 = -123
        var buffer: [UInt8] = []
        value.text.render(appending: &buffer)
        #expect(String(decoding: buffer, as: UTF8.self) == "-123")
    }

    @Test func renderZero() {
        let value: Decimal.Format64 = 0
        var buffer: [UInt8] = []
        value.text.render(appending: &buffer)
        #expect(String(decoding: buffer, as: UTF8.self) == "0")
    }

    @Test func renderInfinity() {
        let value = Decimal.Format64.infinity()
        var buffer: [UInt8] = []
        value.text.render(appending: &buffer)
        #expect(String(decoding: buffer, as: UTF8.self) == "Infinity")
    }

    @Test func renderNegativeInfinity() {
        let value = Decimal.Format64.infinity(sign: .negative)
        var buffer: [UInt8] = []
        value.text.render(appending: &buffer)
        #expect(String(decoding: buffer, as: UTF8.self) == "-Infinity")
    }

    @Test func renderNaN() {
        let value = Decimal.Format64.nan()
        var buffer: [UInt8] = []
        value.text.render(appending: &buffer)
        #expect(String(decoding: buffer, as: UTF8.self) == "NaN")
    }
}
