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

        // MARK: - F-003 revision 1 (orchestrator-directed)

        @Test func `fuse computes the exact sum within the guard-digit window instead of dropping a still-significant operand`() {
            // F-003 revision 1: fuse()'s alignment fallback used to trigger the
            // instant scaling overflowed UInt128, which — because the unrounded
            // product coefficient can already carry up to twice Format64's
            // 16-digit precision — could fire while the discarded operand was
            // still within `precision` digits of affecting the correctly-
            // rounded result.
            //
            // x*y = 5000000000000000 * 7000000000000001 =
            // 35000000000000005000000000000000 (32 digits) at exponent 0; z =
            // 1234567 at exponent -10 (gap 10, well inside the "precision + 2"
            // = 18 digit guard window). x and y are deliberately constructed so
            // the unrounded product's rounding boundary lands on an EXACT
            // round-half-even tie (remainder exactly half the divisor,
            // quotient already even) — the sharpest form of this bug:
            // discarding z entirely (as the pre-revision fallback did the
            // instant scaling overflowed UInt128) makes the tie look exact and
            // rounds it down to an even quotient (3500000000000000); folding in
            // z as a sticky (nonzero, not-exactly-half) contribution is the
            // only thing that correctly breaks the tie upward
            // (3500000000000001) per round-half-even semantics, regardless of
            // how numerically tiny z is relative to the product. Expected value
            // verified by independent bignum arithmetic (Python), not by the
            // implementation under test.
            //
            // KNOWN INTERACTION: swift-decimal-primitives' BID encode/decode
            // disagreement (documented in the pre-revision REPORT.md as
            // affecting Format64 "exponents in [370, 384]") empirically also
            // mangles ANY exponent once the coefficient's leading digit is 8 or
            // 9 (BID "Form 2" encoding) — confirmed by direct round-trip probe:
            // a 16-digit coefficient of 9s at exponent 2 decodes back as
            // exponent 402, not 2. Routed around by keeping every coefficient's
            // leading digit at or below 7 (BID "Form 1"), which round-trips
            // correctly. Not a fix to that repo — just avoiding its known-bad
            // input class, per this revision's brief.
            let x = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 5_000_000_000_000_000)
            let y = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 7_000_000_000_000_001)
            let z = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(-10), coefficient: 1_234_567)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(16), coefficient: 3_500_000_000_000_001)
            #expect(result.value != z)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }

        // MARK: - F-002/F-003 revision 2 (digit-position-aware decision)

        @Test func `fuse still computes the exact sum when the product has fewer digits than the fixed guard window assumed`() {
            // Revision 1's `precision + 2` fixed guard-digit window (18 for
            // Format64) silently assumed the dominant (near) operand always
            // carries close to `precision` digits of its own. It does not:
            // x = y = 1, so the unrounded product is exactly 1 (1 digit) at
            // exponent 0 — the operand the drop path would otherwise return
            // bare. z = 5000000000000000 (16 digits, leading digit 5 — see
            // the KNOWN INTERACTION note above for why leading digit 8/9 is
            // avoided) at exponent -25 (gap 25). Revision 1's fixed window
            // already fires here (25 >= 18), dropping z entirely and
            // returning bare product = 1, discarding a genuinely significant
            // operand. The digit-position-aware threshold is `precision +
            // digits(z) - digits(product)` = `16 + 16 - 1` = 31: 25 does not
            // clear it, so the exact sum must still be computed. Expected
            // value verified by independent bignum arithmetic (Python); the
            // exact sum needs only 16 significant digits, so this is a
            // lossless (non-`.inexact`) result.
            let x = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let y = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(-25), coefficient: 5_000_000_000_000_000)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(-15), coefficient: 1_000_000_000_500_000)
            #expect(result.value != x)
            #expect(result.value == expected)
            #expect(!result.status.contains(.inexact))
        }

        // MARK: - F-002/F-003 revision 5 (product-dominates same-sign
        // near-tie widening, [INST-TEST-013])

        @Test func `fuse rounds a same-sign near tie in the product's own digits correctly when z is not negligible`() {
            // Revision 4 fixed the opposite-sign sign-drop but deliberately
            // left the SAME-SIGN drop path bit-for-bit unchanged (bare
            // `threshold`, no widening). That path is unsound too: once
            // `diff` exceeds the bare `threshold` but is still `<=
            // digitsFar`, z's magnitude (bounded by `10^digitsFar`) can be
            // large enough to cross a round-half-even boundary that a
            // boolean `sticky: true` cannot represent (it can only ever
            // mean "some nonzero amount less than 1 unit").
            //
            // x = 8190249936086788, y = 917372637240375: product =
            // 7513511183525749496806817665500 (31 digits) at exponent 0.
            // z = +6635049452689808E-3 (digitsFar = 16, same sign).
            // digitsNear = 31 > precision (16) collapses the bare threshold
            // to `16 + 16 - 31 + 1` = 2; the gap (3) exceeds it and is `<=
            // digitsFar` (16), landing in the old drop path even though z
            // is NOT negligible. True value rounds (round-half-even, 16
            // significant digits) UP to 7513511183525750E15 — not down to
            // the bare product's own leading 16 digits, 7513511183525749E15.
            // Independently verified with an exact-`Fraction` Python oracle
            // (no floating-point or bounded-precision `Decimal` context
            // involved).
            let x = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 8_190_249_936_086_788)
            let y = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 917_372_637_240_375)
            let z = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(-3), coefficient: 6_635_049_452_689_808)
            let result = x.operation.fuse(y, z)
            let wrongPreFix = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(15), coefficient: 7_513_511_183_525_749)
            let expected = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(15), coefficient: 7_513_511_183_525_750)
            #expect(result.value != wrongPreFix)
            #expect(result.value == expected)
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
            // x = 4000000000000001 (16 digits), y = 5: product =
            // 20000000000000005 (17 digits) at exponent 0 — an EXACT
            // round-half-even tie at Format64's 16-digit rounding boundary
            // (dropped digit exactly 5, kept quotient 2000000000000000 is
            // even). z = -1E-2 (digitsFar = 1), opposite sign. digitsNear =
            // 17 > precision (16) collapses the drop threshold to
            // `16 + 1 - 17 + 1` = 1; the gap (2) exceeds it, landing in the
            // drop path.
            //
            // True value: 20000000000000005 - 0.01 = 20000000000000004.99,
            // strictly below the tie, so round-half-even rounds DOWN to the
            // even quotient 2000000000000000 at exponent 1 — not UP to
            // …001. Independently verified with Python `decimal` (prec=16,
            // ROUND_HALF_EVEN): `Decimal('20000000000000005') +
            // Decimal('-0.01')` rounded to 16 significant digits.
            let x = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 4_000_000_000_000_001)
            let y = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 5)
            let z = Decimal.Format64.encode(sign: .negative, exponent: Decimal.Exponent(-2), coefficient: 1)
            let result = x.operation.fuse(y, z)
            let wrongPreFix = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(1), coefficient: 2_000_000_000_000_001)
            let expected = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(1), coefficient: 2_000_000_000_000_000)
            #expect(result.value != wrongPreFix)
            #expect(result.value == expected)
        }

        // MARK: - F-002/F-003 revision 3 (opposite-sign borrow off-by-one)

        @Test func `fuse does not drop a still-significant addend across an opposite-sign borrow when the product is a power of ten`() {
            // Same off-by-one argument as the Format128 case (see
            // Format128.Arithmetic.swift's revision 3 tests for the full
            // borrow-cascade derivation): x = 1E17, y = 1E0, so the unrounded
            // product is exactly 1 (digitsNear = 1) at exponent 17 — a power
            // of ten, the dominant operand the drop path would otherwise
            // return bare. z = -6 at exponent 0 (digitsFar = 1, opposite sign
            // from the product). The old (revision 2) threshold is
            // `16 + 1 - 1` = 16; the gap (17) exceeds it by exactly one, so
            // revision 2 still drops z and returns bare product = 1E17. The
            // true value 1E17 - 6 = 99999999999999994 (17 digits) rounds
            // (round-half-even, dropped digit 4 < 5, round down) to the
            // 16-digit 9999999999999999E1 = 1E17 - 10 — not bare product.
            // Expected value verified by independent bignum arithmetic
            // (Python: `Decimal('1e17') + Decimal(-6)`, rounded to 16
            // significant digits), not by the implementation under test. No
            // coefficient here has leading digit 8 or 9 as an INPUT operand
            // (only the expected OUTPUT coefficient does), so this does not
            // hit the KNOWN INTERACTION BID Form-2 decode bug documented
            // above: `Decimal.Format64` is `Hashable`/`Equatable` over its raw
            // `bits` storage, and both `result.value` and `expected` are
            // produced by the same deterministic `encode(sign:exponent:
            // coefficient:)` — the comparison never calls `extractExponent`/
            // `extractCoefficient` (the buggy decode path) on either side.
            let x = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(17), coefficient: 1)
            let y = Decimal.Format64.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format64.encode(sign: .negative, exponent: Decimal.Exponent(0), coefficient: 6)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format64.encode(
                sign: .positive, exponent: Decimal.Exponent(1),
                coefficient: 9_999_999_999_999_999
            )
            #expect(result.value != x)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }
    }
}
