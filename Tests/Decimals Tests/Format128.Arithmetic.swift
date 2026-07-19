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

        // MARK: - F-002/F-003 revision 2 (digit-position-aware decision)

        @Test func `addition still computes the exact sum when the near operand has fewer digits than the fixed guard window assumed`() {
            // Revision 1's `precision + 2` fixed guard-digit window (36 for
            // Format128) assumed the near/dominant operand always carries
            // close to `precision` digits of its own. It does not: here B has
            // only 1 digit, so the retained `precision`-digit window below
            // B's most significant digit reaches much further down than the
            // fixed window accounted for. Concrete case: A =
            // 5000000000000000000000000000000000 (34 digits, leading digit 5
            // to dodge the BID Form-2 leading-digit-8-or-9 encode/decode bug —
            // see the KNOWN INTERACTION note elsewhere in this suite) at
            // exponent 0; B = 1 at exponent 36 (gap 36 — exactly the old fixed
            // window's boundary, so revision 1's code takes the drop branch
            // and returns bare B = 1e36). The true sum is
            // 1005000000000000000000000000000000000 = 1.005e36: A is NOT
            // negligible, it changes the 3rd significant digit. The
            // digit-position-aware condition requires `diff > digits(far) -
            // digits(near) + precision` = `34 - 1 + 34` = `67` before a drop
            // is safe; 36 does not clear that bar, so the exact sum must be
            // computed. The exact sum needs only 4 significant digits (1005),
            // well inside the 34-digit precision, so this is a lossless
            // result: no rounding occurs and `.inexact` must NOT be raised.
            // Expected value verified by independent bignum arithmetic
            // (Python), not by the implementation under test.
            let a = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(0),
                coefficient: 5_000_000_000_000_000_000_000_000_000_000_000
            )
            let b = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(36), coefficient: 1)
            let result = a.operation.add(b)
            let expected = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(3),
                coefficient: 1_005_000_000_000_000_000_000_000_000_000_000
            )
            #expect(result.value != b)
            #expect(result.value == expected)
            #expect(!result.status.contains(.inexact))
        }

        @Test func `fuse still computes the exact sum when the product has fewer digits than the fixed guard window assumed`() {
            // Same digit-position argument as the add() case immediately
            // above, generalized to fuse(): x = y = 1, so the unrounded
            // product is exactly 1 (1 digit) at exponent 0 — the dominant
            // operand the drop path would otherwise return bare. z =
            // 5000000000000000000000000000000000 (34 digits, leading digit 5)
            // at exponent -50 (gap 50). Revision 1's fixed window
            // (`precision + 2` = 36) already fires here (50 >= 36), dropping
            // z entirely and returning bare product = 1 — a ~0.0000000005%
            // relative loss that is nonetheless a real, silently discarded
            // significant digit. The digit-position-aware threshold is
            // `precision + digits(z) - digits(product)` = `34 + 34 - 1` = 67:
            // 50 does not clear it, so the exact sum must still be computed.
            // Expected value verified by independent bignum arithmetic
            // (Python): the exact sum needs only 34 significant digits, so
            // this is again a lossless (non-`.inexact`) result.
            let x = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let y = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(-50),
                coefficient: 5_000_000_000_000_000_000_000_000_000_000_000
            )
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(-33),
                coefficient: 1_000_000_000_000_000_050_000_000_000_000_000
            )
            #expect(result.value != x)
            #expect(result.value == expected)
            #expect(!result.status.contains(.inexact))
        }

        // MARK: - F-002/F-003 revision 4 (product-dominates opposite-sign
        // exact-tie sign drop, [INST-TEST-013])

        @Test func `fuse rounds an exact tie in the product's own digits toward the correct side when z is opposite sign`() {
            // Revision 3 fixed the off-by-one in the drop DECISION threshold.
            // This is a DIFFERENT defect in the drop COMPUTATION: once the
            // decision routes to the drop path, the code rounds the bare
            // product with `sticky: true` unconditionally — which always
            // nudges an exact round-half-even tie UP. That is correct only
            // when the discarded z shares the product's sign; for
            // opposite-sign z it silently rounds the WRONG way on an exact
            // tie, at any distance, because z's sign (not magnitude) decides
            // which side of the tie the true value actually falls on.
            //
            // x = 4000000000000000000000000000000001 (34 digits), y = 5:
            // product = 20000000000000000000000000000000005 (35 digits) at
            // exponent 0 — an EXACT round-half-even tie at Format128's
            // 34-digit rounding boundary (dropped digit is exactly 5, kept
            // quotient 2000000000000000000000000000000000 is even, so the
            // pre-revision-4 code's `sticky: true` rounds it UP regardless).
            // z = -1E-2 (digitsFar = 1), opposite sign. digitsNear =
            // digitCount(35-digit product) = 35 > precision (34), which
            // collapses the drop threshold to `34 + 1 - 35 + 1` = 1; the gap
            // (2) exceeds it, landing in the drop path.
            //
            // True value: 20000000000000000000000000000000005 - 0.01 =
            // 20000000000000000000000000000000004.99, which is strictly
            // BELOW the tie (…004.99 < …005), so round-half-even rounds DOWN
            // to the even quotient 2000000000000000000000000000000000 at
            // exponent 1 — not UP to …001. Independently verified with
            // Python `decimal` (prec=34, ROUND_HALF_EVEN):
            // `Decimal('20000000000000000000000000000000005') + Decimal('-0.01')`
            // rounded to 34 significant digits.
            let x = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(0),
                coefficient: 4_000_000_000_000_000_000_000_000_000_000_001
            )
            let y = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 5)
            let z = Decimal.Format128.encode(sign: .negative, exponent: Decimal.Exponent(-2), coefficient: 1)
            let result = x.operation.fuse(y, z)
            let wrongPreFix = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(1),
                coefficient: 2_000_000_000_000_000_000_000_000_000_000_001
            )
            let expected = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(1),
                coefficient: 2_000_000_000_000_000_000_000_000_000_000_000
            )
            #expect(result.value != wrongPreFix)
            #expect(result.value == expected)
        }

        // MARK: - F-002/F-003 revision 3 (opposite-sign borrow off-by-one)

        @Test func `addition does not drop a still-significant operand across an opposite-sign borrow through a power-of-ten leading digit`() {
            // Revision 2's digit-position-aware threshold (`diff > digits(far) -
            // digits(near) + precision`) is sound for SAME-sign addition, but
            // off by one for OPPOSITE-sign addition (effective subtraction)
            // when the dominant (near) operand's coefficient is a power of ten
            // (here, exactly `1`): subtracting even a single-digit far operand
            // borrows through the near operand's leading digit, which is `1`
            // and so vanishes entirely rather than decrementing to a nonzero
            // digit — shifting the true result's most-significant-digit
            // position down by exactly one decade relative to what the
            // digit-count-only formula assumes. B = 1 at exponent 35
            // (digitsNear = 1), A = -6 at exponent 0 (digitsFar = 1); the old
            // (revision 2) threshold is `34 + 1 - 1` = 34, and the gap (35)
            // exceeds it by exactly one, so revision 2 still takes the drop
            // branch and returns bare B = 1E35. The true difference
            // 1E35 - 6 = 99999999999999999999999999999999994 (35 digits)
            // rounds (round-half-even, dropped digit 4 < 5, round down) to the
            // 34-digit 9999999999999999999999999999999999E1 = 1E35 - 10 — not
            // bare B. Expected value verified by independent bignum arithmetic
            // (Python: `Decimal(-6) + Decimal('1e35')`, rounded to 34
            // significant digits), not by the implementation under test.
            let a = Decimal.Format128.encode(sign: .negative, exponent: Decimal.Exponent(0), coefficient: 6)
            let b = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(35), coefficient: 1)
            let result = a.operation.add(b)
            let expected = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(1),
                coefficient: 9_999_999_999_999_999_999_999_999_999_999_999
            )
            #expect(result.value != b)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }

        @Test func `fuse does not drop a still-significant addend across an opposite-sign borrow when the product is a power of ten`() {
            // Same borrow-cascade argument as the addition case immediately
            // above, generalized to fuse(): x = 1E35, y = 1E0, so the
            // unrounded product is exactly 1 (digitsNear = 1) at exponent 35 —
            // a power of ten, the dominant operand the drop path would
            // otherwise return bare. z = -6 at exponent 0 (digitsFar = 1,
            // opposite sign from the product). The old (revision 2) threshold
            // is `34 + 1 - 1` = 34; the gap (35) exceeds it by exactly one, so
            // revision 2 still drops z and returns bare product = 1E35. The
            // true value, 1E35 - 6, rounds to the same
            // 9999999999999999999999999999999999E1 as the addition case above.
            // Expected value verified by independent bignum arithmetic
            // (Python).
            let x = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(35), coefficient: 1)
            let y = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 1)
            let z = Decimal.Format128.encode(sign: .negative, exponent: Decimal.Exponent(0), coefficient: 6)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(1),
                coefficient: 9_999_999_999_999_999_999_999_999_999_999_999
            )
            #expect(result.value != x)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }

        @Test func `fuse computes the exact sum without trapping at the new threshold's worst-case 74-digit Wide span`() {
            // Overflow-headroom check (revision 3 step 3): widening the
            // exact-vs-drop threshold by one digit widens the worst-case
            // `Decimals.Wide` span this exact branch can be asked to hold. The
            // "z dominates the product" branch (`productExp < zExp`) scales z
            // (the near operand) up by `10^diff`, so its span is
            // `digits(near=z) + diff`. At the new threshold boundary
            // (`diff == precision + digits(far=product) - digits(near=z) + 1`)
            // with `digits(near=z)` at its minimum (1) and `digits(far=product)`
            // at its practical maximum (the unrounded product's own checked
            // `coeffX * coeffY` multiplication traps before it can exceed
            // UInt128's ~39-digit capacity), the span is
            // `1 + (34 + 39 - 1 + 1)` = 74 digits — up from revision 2's 73,
            // still comfortably inside `Decimals.Wide`'s 256-bit (~78-digit)
            // capacity.
            //
            // x = 9999999999999999999999999999999999 (34 nines, Format128's
            // own coefficient max) and y = 34028 are chosen so the unrounded
            // product (x * y = 340279999999999999999999999999999965972, 39
            // digits) is as large as possible without its own checked
            // multiplication trapping. z = -1 at exponent 73 puts the gap
            // (`73 - 0`) exactly on the new threshold boundary (`34 + 39 - 1 +
            // 1` = 73) — the tightest gap that must still be computed exactly
            // rather than dropped, and the one that produces the worst-case
            // 74-digit span above. The assertion is twofold: this call must
            // not trap (a widened window that overflowed `Decimals.Wide`
            // would crash the process, not fail an assertion), and the
            // rounded result must be the correctly-rounded 34-digit value —
            // not the drop path's bare (non-canonicalized) z, which is a
            // different bit pattern despite representing the same real number
            // here. Expected value verified by independent bignum arithmetic
            // (Python), replicating this file's exact `Decimals.Wide`
            // reduction and `round128` algorithm step by step.
            let x = Decimal.Format128.encode(
                sign: .positive, exponent: Decimal.Exponent(0),
                coefficient: 9_999_999_999_999_999_999_999_999_999_999_999
            )
            let y = Decimal.Format128.encode(sign: .positive, exponent: Decimal.Exponent(0), coefficient: 34_028)
            let z = Decimal.Format128.encode(sign: .negative, exponent: Decimal.Exponent(73), coefficient: 1)
            let result = x.operation.fuse(y, z)
            let expected = Decimal.Format128.encode(
                sign: .negative, exponent: Decimal.Exponent(40),
                coefficient: 1_000_000_000_000_000_000_000_000_000_000_000
            )
            #expect(result.value != z)
            #expect(result.value == expected)
            #expect(result.status.contains(.inexact))
        }
    }
}
