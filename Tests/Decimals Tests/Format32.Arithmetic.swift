import Testing

@testable import Decimals

extension Decimal.Format32.Test {
    @Suite struct `Edge Case` {

        // MARK: - Addition

        @Test func `addition does not overflow coefficient scaling at large exponent difference`() {
            // exponent difference of 20 matches the old fixed threshold
            // (`diff.rawValue > 20`) in Add.swift; scaling coeffA by 10^20 overflows
            // UInt64 partway through the naive multiply loop (F-002).
            let a = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let b = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(-20), coefficient: 1)
            let result = a.operation.add(b)
            #expect(!result.value.test.nan)
        }

        // MARK: - Fuse

        @Test func `fuse does not silently combine unaligned coefficients when exponent difference exceeds old cutoff`() {
            // x*y = 1 at exponent 0; z = 1 at exponent -30. The exponent difference
            // (30) exceeds the old fixed cutoff (`diff.rawValue <= 20`), which used
            // to leave both coefficients unscaled and combine them as if they shared
            // an exponent, yielding 1 + 1 = 2 instead of the correct (product
            // dominates; z is negligible beyond Format32's 7-digit precision) ~1 (F-003).
            let x = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let y = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(-30), coefficient: 1)
            let result = x.operation.fuse(y, z)
            #expect(result.value == Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1))
        }

        // MARK: - Divide

        @Test func `divide does not double-round an exact-looking tie that is actually above half`() {
            // 1 / 56239, scaled for Format32's precision, produces a quotient whose
            // last rounding-boundary digits look like an exact tie (5000 of 10000),
            // but the raw division has a nonzero remainder (55000) beyond those
            // digits — the true value is strictly above the tie point, not AT it.
            // Under `.toward` rounding (ties toward zero; otherwise round toward
            // zero), an exact tie truncates but a value strictly above half rounds
            // away from zero. Without passing that "sticky" remainder through to the
            // rounding kernel, this double-rounds to the wrong (truncated) result (F-003).
            var context = Decimal.Context.format32
            context.rounding = .toward
            let a = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let b = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 56239)
            let result = a.operation.divide(b, context: context)
            let expected = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(-11), coefficient: 1_778_126)
            #expect(result.value == expected)
        }

        // MARK: - F-003 revision 1 (orchestrator-directed)

        @Test func `fuse computes the exact sum within the guard-digit window instead of dropping a still-significant operand`() {
            // F-003 revision 1: fuse()'s alignment fallback used to trigger the
            // instant scaling overflowed UInt64, which — because the unrounded
            // product coefficient can already carry up to twice Format32's
            // 7-digit precision — could fire while the discarded operand was
            // still within `precision` digits of affecting the correctly-
            // rounded result.
            //
            // x*y = 5000000 * 7000001 = 35000005000000 (14 digits) at exponent
            // 0; z = 1234567 at exponent -7 (gap 7, well inside the
            // "precision + 2" = 9 digit guard window). x and y are deliberately
            // constructed so the unrounded product's rounding boundary lands on
            // an EXACT round-half-even tie (remainder exactly half the
            // divisor, quotient already even) — the sharpest form of this bug:
            // discarding z entirely (as the pre-revision fallback did the
            // instant scaling overflowed UInt64) makes the tie look exact and
            // rounds it down to an even quotient (3500000); folding in z as a
            // sticky (nonzero, not-exactly-half) contribution is the only thing
            // that correctly breaks the tie upward (3500001) per round-half-even
            // semantics, regardless of how numerically tiny z is relative to
            // the product. Expected value verified by independent bignum
            // arithmetic (Python), not by the implementation under test.
            let x = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 5_000_000)
            let y = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 7_000_001)
            let z = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(-7), coefficient: 1_234_567)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(7), coefficient: 3_500_001)
            #expect(result.value != z)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }

        // MARK: - F-002/F-003 revision 2 (digit-position-aware decision)

        @Test func `fuse still computes the exact sum when the product has fewer digits than the fixed guard window assumed`() {
            // Revision 1's `precision + 2` fixed guard-digit window (9 for
            // Format32) silently assumed the dominant (near) operand always
            // carries close to `precision` digits of its own. It does not:
            // x = y = 1, so the unrounded product is exactly 1 (1 digit) at
            // exponent 0 — the operand the drop path would otherwise return
            // bare. z = 5000000 (7 digits, leading digit 5) at exponent -11
            // (gap 11). Revision 1's fixed window already fires here
            // (11 >= 9), dropping z entirely and returning bare product = 1,
            // discarding a genuinely significant operand. The
            // digit-position-aware threshold is `precision + digits(z) -
            // digits(product)` = `7 + 7 - 1` = 13: 11 does not clear it, so
            // the exact sum must still be computed. Expected value verified
            // by independent bignum arithmetic (Python); the exact sum needs
            // only 7 significant digits, so this is a lossless
            // (non-`.inexact`) result.
            let x = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let y = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(-11), coefficient: 5_000_000)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(-6), coefficient: 1_000_050)
            #expect(result.value != x)
            #expect(result.value == expected)
            #expect(!result.status.contains(.inexact))
        }

        // MARK: - F-002/F-003 revision 4 (product-dominates opposite-sign
        // exact-tie sign drop, [INST-TEST-013])

        @Test func `fuse rounds an exact tie in the product's own digits toward the correct side when z is opposite sign`() {
            // Same defect and derivation as the Format128 case (see
            // Format128.Arithmetic.swift's revision 4 test for the full
            // write-up): the drop path's `sticky: true` always nudges an
            // exact round-half-even tie in the product's own digits UP,
            // which is wrong when the discarded z is opposite sign — z's
            // sign, not magnitude, decides which side of the tie the true
            // value falls on, at any distance.
            //
            // x = 4000001 (7 digits), y = 5: product = 20000005 (8 digits)
            // at exponent 0 — an EXACT round-half-even tie at Format32's
            // 7-digit rounding boundary (dropped digit exactly 5, kept
            // quotient 2000000 is even). z = -1E-2 (digitsFar = 1),
            // opposite sign. digitsNear = 8 > precision (7) collapses the
            // drop threshold to `7 + 1 - 8 + 1` = 1; the gap (2) exceeds it,
            // landing in the drop path.
            //
            // True value: 20000005 - 0.01 = 20000004.99, strictly below the
            // tie, so round-half-even rounds DOWN to the even quotient
            // 2000000 at exponent 1 — not UP to 2000001. Independently
            // verified with Python `decimal` (prec=7, ROUND_HALF_EVEN):
            // `Decimal('20000005') + Decimal('-0.01')` rounded to 7
            // significant digits.
            let x = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 4_000_001)
            let y = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 5)
            let z = Decimal.Format32.encode(sign: .negative, exponent: Decimal.Exponent(-2), coefficient: 1)
            let result = x.operation.fuse(y, z)
            let wrongPreFix = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(1), coefficient: 2_000_001)
            let expected = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(1), coefficient: 2_000_000)
            #expect(result.value != wrongPreFix)
            #expect(result.value == expected)
        }

        // MARK: - F-002/F-003 revision 3 (opposite-sign borrow off-by-one)

        @Test func `fuse does not drop a still-significant addend across an opposite-sign borrow when the product is a power of ten`() {
            // Same off-by-one argument as the Format128 case (see
            // Format128.Arithmetic.swift's revision 3 tests for the full
            // borrow-cascade derivation): x = 1E8, y = 1E0, so the unrounded
            // product is exactly 1 (digitsNear = 1) at exponent 8 — a power of
            // ten, the dominant operand the drop path would otherwise return
            // bare. z = -6 at exponent 0 (digitsFar = 1, opposite sign from
            // the product). The old (revision 2) threshold is `7 + 1 - 1` = 7;
            // the gap (8) exceeds it by exactly one, so revision 2 still drops
            // z and returns bare product = 1E8. The true value 1E8 - 6 =
            // 99999994 (8 digits) rounds (round-half-even, dropped digit 4 <
            // 5, round down) to the 7-digit 9999999E1 = 1E8 - 10 — not bare
            // product. Expected value verified by independent bignum
            // arithmetic (Python: `Decimal('1e8') + Decimal(-6)`, rounded to 7
            // significant digits), not by the implementation under test. As
            // with Format64, only the expected OUTPUT coefficient carries a
            // leading digit 9 — the INPUT operands do not — and the
            // `Decimal.Format32` comparison is raw-`bits` equality between two
            // `encode(...)` calls, so the KNOWN INTERACTION BID Form-2 decode
            // bug documented in Format32.Text.swift is not in play here.
            let x = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(8), coefficient: 1)
            let y = Decimal.Format32.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format32.encode(sign: .negative, exponent: Decimal.Exponent(0), coefficient: 6)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format32.encode(
                sign: .positive, exponent: Decimal.Exponent(1),
                coefficient: 9_999_999
            )
            #expect(result.value != x)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }
    }
}
