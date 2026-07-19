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

        // MARK: - F-002/F-003 revision 1 (orchestrator-directed)

        @Test func `addition computes the exact sum within the guard-digit window instead of dropping a still-significant operand`() {
            // F-002 revision 1: Format128's headroom above its own precision
            // (UInt128's ~38-39 digit capacity minus this format's 34-digit
            // precision — only ~4-5 digits) is too narrow to assume the smaller
            // operand is negligible merely because scaling it to align would
            // overflow UInt128. Concrete failing case from the orchestrator's
            // review: exponent gap 5 is well within the "precision + 2" (36)
            // guard-digit window, so B is still significant — the pre-revision
            // fallback silently returned exactly `b`, dropping A entirely and
            // landing roughly 10x too small (true sum's leading digit carries
            // into a higher exponent than `b` alone). Expected value verified by
            // independent bignum arithmetic (Python), not by the implementation
            // under test.
            let a = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(0),
                coefficient: 9_999_999_999_999_999_999_999_999_999_999_999
            )
            let b = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(5),
                coefficient: 9_999_999_999_999_999_999_999_999_999_999_999
            )
            let result = a.operation.add(b)
            let expected = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(6),
                coefficient: 1_000_010_000_000_000_000_000_000_000_000_000
            )
            #expect(result.value != b)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }

        @Test func `addition beyond the guard-digit window folds the discarded operand into the rounding decision as sticky`() {
            // Beyond `precision + 2` (36), the discarded operand cannot change
            // any retained or guard digit of the dominant operand (already
            // valid at <= 34 digits), so the shortcut is sound — but it must
            // still raise `.inexact` for the discarded, nonzero operand.
            let a = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let b = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(-40), coefficient: 1)
            let result = a.operation.add(b)
            #expect(result.value == a)
            #expect(result.status.contains(.inexact))
        }

        @Test func `fuse computes the exact sum within the guard-digit window instead of dropping a still-significant operand`() {
            // Same guard-digit argument as add() above, generalized to fuse()
            // via x=1 (so the product is exactly y, and this branch — z's
            // exponent exceeds the product's — mirrors add()'s own scale-the-
            // larger-exponent-operand branch exactly): x*y =
            // 9999999999999999999999999999999999 (34 nines) at exponent 0,
            // z = the same 34-nines coefficient at exponent 5 (gap 5 — the
            // same gap as the add() case above, since Format128's headroom (4
            // digits) is exceeded by any gap > 4 but this is still well inside
            // the 36-digit guard window). Expected value verified by
            // independent bignum arithmetic (Python). A gap of 2 (tried first)
            // does NOT exceed Format128's 4-digit headroom, so it does not
            // reproduce the pre-revision bug — the pre-revision fallback only
            // fires once scaling would actually overflow UInt128, which needs
            // gap > headroom, not merely gap < the new guard window.
            let x = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let y = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(0),
                coefficient: 9_999_999_999_999_999_999_999_999_999_999_999
            )
            let z = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(5),
                coefficient: 9_999_999_999_999_999_999_999_999_999_999_999
            )
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(6),
                coefficient: 1_000_010_000_000_000_000_000_000_000_000_000
            )
            #expect(result.value != z)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }
    }
}
