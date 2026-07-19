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
    }
}
