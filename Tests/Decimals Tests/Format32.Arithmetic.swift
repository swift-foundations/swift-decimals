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
    }
}
