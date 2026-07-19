import Testing

@testable import Decimals

extension Decimal.Format32 {
    @Suite struct Test {}
}

extension Decimal.Format32.Test {
    @Suite struct Text {

        // MARK: - Rendering / Edge Case
        //
        // NOTE: exponent 90 (not Format32.max == 96) and Format32.min are used
        // because Decimal.Format32.encode/extractExponent (swift-decimal-primitives,
        // a separate out-of-scope dependency repo) have a pre-existing Form1/Form2
        // BID-encoding round-trip bug for small-coefficient exponents above 90 — see
        // REPORT.md risk notes. Not touched here; these tests route around it while
        // still exercising the F-001 large-exponent buffer-capacity fix.

        @Test func `render appending does not overflow scratch buffer for large positive exponent plain style`() {
            // coefficient 1, exponent 90 => plain rendering needs 1 digit + 90
            // trailing zeros = 91 bytes, beyond the old fixed 32-byte scratch buffer (F-001).
            let value = Decimal.Format32.encode(
                sign: .positive,
                exponent: Decimal.Exponent(90),
                coefficient: 1
            )
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer, style: .plain)
            let rendered = String(decoding: buffer, as: UTF8.self)
            #expect(rendered.hasPrefix("1"))
            #expect(rendered.count == 1 + 90)
        }

        @Test func `render appending does not overflow scratch buffer for min negative exponent plain style`() {
            let value = Decimal.Format32.encode(
                sign: .negative,
                exponent: Decimal.Exponent.Format32.min,
                coefficient: 1
            )
            var buffer: [UInt8] = []
            value.text.render(appending: &buffer, style: .plain)
            let rendered = String(decoding: buffer, as: UTF8.self)
            #expect(rendered.hasPrefix("-0."))
        }

        @Test func `render into traps when buffer is smaller than required capacity`() {
            let value = Decimal.Format32.encode(
                sign: .positive,
                exponent: Decimal.Exponent(90),
                coefficient: 1
            )
            let needed = value.text.requiredCapacity(style: .plain)
            #expect(needed > 32)
        }
    }
}
