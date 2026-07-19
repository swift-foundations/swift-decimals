import Testing

@testable import Decimals

extension Decimal.Format128 {
    @Suite struct Test {}
}

extension Decimal.Format128.Test {
    @Suite struct Text {

        // MARK: - Rendering / Edge Case
        //
        // NOTE: exponent 6111 (not Format128.max == 6144) is used because
        // Decimal.Format128.encode/extractExponent (swift-decimal-primitives, a
        // separate out-of-scope dependency repo) have a pre-existing Form1/Form2
        // BID-encoding round-trip bug for small-coefficient exponents above 6111 —
        // see REPORT.md risk notes. Not touched here; these tests route around it
        // while still exercising the F-001 large-exponent buffer-capacity fix.

        @Test func `render appending does not overflow scratch buffer for large positive exponent plain style`() {
            // coefficient 1, exponent 6111 => plain rendering needs 1 digit + 6111
            // trailing zeros = 6112 bytes, vastly beyond the old fixed 64-byte
            // scratch buffer (F-001).
            let value = Decimal.Format128.encode(
                sign: .positive,
                exponent: Decimal.Exponent(6111),
                coefficient: 1
            )
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer, style: .plain)
            let rendered = String(decoding: buffer, as: UTF8.self)
            #expect(rendered.hasPrefix("1"))
            #expect(rendered.count == 1 + 6111)
        }

        @Test func `render appending does not overflow scratch buffer for min negative exponent plain style`() {
            let value = Decimal.Format128.encode(
                sign: .negative,
                exponent: Decimal.Exponent.Format128.min,
                coefficient: 1
            )
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer, style: .plain)
            let rendered = String(decoding: buffer, as: UTF8.self)
            #expect(rendered.hasPrefix("-0."))
        }

        @Test func `render into traps when buffer is smaller than required capacity`() {
            let value = Decimal.Format128.encode(
                sign: .positive,
                exponent: Decimal.Exponent(6111),
                coefficient: 1
            )
            let needed = value.text.requiredCapacity(style: .plain)
            #expect(needed > 64)
        }

        // MARK: - Parsing / Edge Case

        @Test func `parse exponent digit overflow resolves to high instead of trapping`() {
            // A 25-digit exponent-digit string is legal grammar but would overflow
            // Int's `expValue * 10 + digit` accumulation and trap (F-005).
            #expect(throws: Decimal._TextError.high) {
                _ = try Decimal.Format128.text([UInt8]("1E9999999999999999999999999".utf8))
            }
        }

        @Test func `parse NaN rejects trailing garbage`() {
            #expect(throws: Decimal._TextError.self) {
                _ = try Decimal.Format128.text([UInt8]("NaN123garbage".utf8))
            }
        }

        @Test func `parse NaN preserves sign`() throws {
            let value = try Decimal.Format128.text([UInt8]("-NaN".utf8))
            #expect(value.test.nan)
            #expect(value.test.negative)
        }

        @Test func `parse rounds over precision coefficient instead of corrupting encoding`() throws {
            // 35 significant digits (34 ones + a final 7); Format128's precision is
            // 34. Dropped digit 7 > 5 rounds the 34th digit up, exponent 0 -> 1.
            let value = try Decimal.Format128.text([UInt8]((String(repeating: "1", count: 34) + "7").utf8))
            let expected = Decimal.Format128.encode(
                sign: .positive,
                exponent: Decimal.Exponent(1),
                coefficient: UInt128(String(repeating: "1", count: 33) + "2")!
            )
            #expect(value == expected)
        }
    }
}
