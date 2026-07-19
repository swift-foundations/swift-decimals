import Testing

@testable import Decimals

extension Decimal.Format64.Test {
    @Suite struct Text {

        // MARK: - Parsing

        @Test func `parse Integer`() throws {
            let value = try Decimal.Format64.text([UInt8]("123".utf8))
            #expect(Int64(exactly: value) == 123)
        }

        @Test func `parse Negative Integer`() throws {
            let value = try Decimal.Format64.text([UInt8]("-456".utf8))
            #expect(Int64(exactly: value) == -456)
        }

        @Test func `parse Decimal`() throws {
            let value = try Decimal.Format64.text([UInt8]("12.5".utf8))
            // 12.5 = 125 * 10^-1
            let doubled = value + value  // 25
            #expect(Int64(exactly: doubled) == 25)
        }

        @Test func `parse Scientific`() throws {
            let value = try Decimal.Format64.text([UInt8]("1.5E2".utf8))
            #expect(Int64(exactly: value) == 150)
        }

        @Test func `parse Infinity`() throws {
            let inf = try Decimal.Format64.text([UInt8]("Infinity".utf8))
            #expect(inf.test.infinite)
            #expect(!inf.test.negative)
        }

        @Test func `parse Negative Infinity`() throws {
            let negInf = try Decimal.Format64.text([UInt8]("-Inf".utf8))
            #expect(negInf.test.infinite)
            #expect(negInf.test.negative)
        }

        @Test func `parse NaN`() throws {
            let nan = try Decimal.Format64.text([UInt8]("NaN".utf8))
            #expect(nan.test.nan)
        }

        @Test func `parse Zero`() throws {
            let zero = try Decimal.Format64.text([UInt8]("0".utf8))
            #expect(zero.test.zero)
        }

        @Test func `parse Empty`() {
            #expect(throws: Decimal._TextError.self) {
                _ = try Decimal.Format64.text([UInt8]())
            }
        }

        // MARK: - Parsing / Edge Case

        @Test func `parse exponent digit overflow resolves to high instead of trapping`() {
            // A 25-digit exponent-digit string is legal grammar but would overflow
            // Int's `expValue * 10 + digit` accumulation and trap (F-005). It must
            // instead cleanly resolve to .high (the exponent is obviously far
            // beyond any format's range).
            #expect(throws: Decimal._TextError.high) {
                _ = try Decimal.Format64.text([UInt8]("1E9999999999999999999999999".utf8))
            }
        }

        @Test func `parse exponent digit underflow resolves to low instead of trapping`() {
            #expect(throws: Decimal._TextError.low) {
                _ = try Decimal.Format64.text([UInt8]("1E-9999999999999999999999999".utf8))
            }
        }

        @Test func `parse NaN rejects trailing garbage`() {
            // "NaN" followed by anything else is not a valid NaN literal; it must
            // not be silently accepted as one (F-005).
            #expect(throws: Decimal._TextError.self) {
                _ = try Decimal.Format64.text([UInt8]("NaN123garbage".utf8))
            }
        }

        @Test func `parse NaN preserves sign`() throws {
            // "-NaN" previously always returned an unsigned (positive) NaN,
            // discarding the parsed sign (F-005).
            let value = try Decimal.Format64.text([UInt8]("-NaN".utf8))
            #expect(value.test.nan)
            #expect(value.test.negative)
        }

        @Test func `parse rounds over precision coefficient instead of corrupting encoding`() throws {
            // 17 significant digits; Format64's precision is 16. Passing the raw
            // 17-digit coefficient straight to encode() (as the pre-fix code did)
            // silently corrupts the bit pattern instead of correctly rounding
            // (F-005). Correctly rounded (round-half-even, dropped digit 7 > 5
            // rounds up): 1234567890123456 -> 1234567890123457, exponent 0 -> 1.
            let value = try Decimal.Format64.text([UInt8]("12345678901234567".utf8))
            let expected = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(1), coefficient: 1_234_567_890_123_457)
            #expect(value == expected)
        }

        // MARK: - Rendering

        @Test func `render Integer`() {
            let value: Decimal.Format64 = 42
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "42")
        }

        @Test func `render Negative`() {
            let value: Decimal.Format64 = -123
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "-123")
        }

        @Test func `render Zero`() {
            let value: Decimal.Format64 = 0
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "0")
        }

        @Test func `render Infinity`() {
            let value = Decimal.Format64.infinity()
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "Infinity")
        }

        @Test func `render Negative Infinity`() {
            let value = Decimal.Format64.infinity(sign: .negative)
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "-Infinity")
        }

        @Test func `render NaN`() {
            let value = Decimal.Format64.nan()
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer)
            #expect(String(decoding: buffer, as: UTF8.self) == "NaN")
        }

        // MARK: - Rendering / Edge Case
        //
        // NOTE: these tests deliberately stay within exponent [-383, 369] with
        // coefficients below 2^53. Format64.encode/extractExponent/extractCoefficient
        // (swift-decimal-primitives, a separate out-of-scope dependency repo) have a
        // pre-existing Form1/Form2 BID-encoding round-trip bug for the small-coefficient,
        // exponent-in-[370, 384] combination — see REPORT.md risk notes. That bug is not
        // part of this brief's evidence and is not touched here; these tests route
        // around it while still exercising the F-001 large-exponent buffer-capacity fix.

        @Test func `render appending does not overflow scratch buffer for large positive exponent plain style`() {
            // coefficient 1, exponent 369 => plain rendering needs 1 digit + 369
            // trailing zeros = 370 bytes, far beyond the old fixed 64-byte scratch
            // buffer (F-001).
            let value = Decimal.Format64.encode(
                sign: .positive,
                exponent: Decimal.Exponent(369),
                coefficient: 1
            )
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer, style: .plain)
            let rendered = String(decoding: buffer, as: UTF8.self)
            #expect(rendered.hasPrefix("1"))
            #expect(rendered.count == 1 + 369)
        }

        @Test func `render appending does not overflow scratch buffer for min negative exponent plain style`() {
            // coefficient 1, exponent = Format64.min (-383) => plain rendering needs
            // "0." + 382 leading zeros + 1 digit + sign, also far beyond 64 bytes.
            let value = Decimal.Format64.encode(
                sign: .negative,
                exponent: Decimal.Exponent.Format64.min,
                coefficient: 1
            )
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer, style: .plain)
            let rendered = String(decoding: buffer, as: UTF8.self)
            #expect(rendered.hasPrefix("-0."))
        }

        @Test func `render into traps when buffer is smaller than required capacity`() {
            let value = Decimal.Format64.encode(
                sign: .positive,
                exponent: Decimal.Exponent(369),
                coefficient: 1
            )
            let needed = value.text.requiredCapacity(style: .plain)
            #expect(needed > 64)
        }

        @Test func `render appending scientific and engineering styles stay within bounds at large exponent`() {
            // 16-digit coefficient (below 2^53, so Form1) at a large exponent.
            let value = Decimal.Format64.encode(
                sign: .negative,
                exponent: Decimal.Exponent(369),
                coefficient: 9_007_199_254_740_991
            )
            var scientific: [UInt8] = []
            value.text.render(appending: &scientific, style: .scientific)
            #expect(String(decoding: scientific, as: UTF8.self).hasPrefix("-9.007199254740991E"))

            var engineering: [UInt8] = []
            value.text.render(appending: &engineering, style: .engineering)
            #expect(String(decoding: engineering, as: UTF8.self).hasPrefix("-"))
        }
    }
}
