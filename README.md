# swift-decimals

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Decimal floating-point arithmetic for Swift — the IEEE 754 decimal interchange formats (`Decimal.Format32`, `Decimal.Format64`, `Decimal.Format128`) with context-controlled rounding, per-operation status flags, and byte-level text parsing and rendering.

---

## Quick Start

Binary floating point cannot represent most decimal fractions exactly; decimal floating point can.

```swift
import Decimals

// Binary floating point rounds silently:
0.1 + 0.2 == 0.3                            // false — 0.30000000000000004

// Decimal arithmetic on the same values is exact:
let a = try Decimal.Format64.text([UInt8]("0.1".utf8))
let b = try Decimal.Format64.text([UInt8]("0.2".utf8))
let sum = a + b

var rendered: [UInt8] = []
sum.text.render(appending: &rendered)
String(decoding: rendered, as: UTF8.self)   // "0.3"
```

Beyond operators, the `operation` accessor reports what happened instead of hiding it — something `Double` cannot do without global floating-point environment state:

```swift
import Decimals

let one: Decimal.Format64 = 1
let three: Decimal.Format64 = 3

let outcome = one.operation.divide(three)
outcome.value                               // 0.3333333333333333 (16 digits)
outcome.status.contains(.inexact)           // true — the result was rounded

// Escalate selected flags into a typed error:
let exact = try outcome.trapped(by: .inexact)   // throws Decimal.Trap<Decimal.Format64>
```

---

## Installation

Add swift-decimals to your `Package.swift` (no tags are published yet; pin to `main`):

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-decimals.git", branch: "main")
]
```

Add the product to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Decimals", package: "swift-decimals")
    ]
)
```

### Requirements

- Swift 6.3+
- macOS 26+, iOS 26+, tvOS 26+, watchOS 26+, visionOS 26+

---

## Key Features

- **Three interchange formats** — `Decimal.Format32`, `Decimal.Format64`, and `Decimal.Format128`, stored in the IEEE 754 binary integer decimal (BID) encoding.
- **Status flags on every operation** — `add`, `multiply`, `divide`, and `fuse` (fused multiply-add) return a `Decimal.Outcome` carrying the result plus `invalid` / `divide` / `overflow` / `underflow` / `inexact` flags; `trapped(by:)` escalates selected flags to a typed `Decimal.Trap` error.
- **Context-controlled arithmetic** — `Decimal.Context` bundles precision, rounding mode (7 modes including round-half-even), trap set, exponent clamping, and tininess detection; `.format32` / `.format64` / `.format128` presets match each format's IEEE parameters.
- **Standard numeric integration** — `ExpressibleByIntegerLiteral`, `AdditiveArithmetic`, `Numeric`, `SignedNumeric`, and `Comparable`, so `+ - * /` and `<` work directly when flag inspection is not needed.
- **Byte-level text I/O** — parsing from `UnsafeBufferPointer<UInt8>`, `ArraySlice<UInt8>`, or `[UInt8]` and rendering in plain, scientific, or engineering style, with no `Foundation` dependency.
- **Typed throws end-to-end** — parsing throws `Decimal.Text.Error`; trapping throws `Decimal.Trap`; no `any Error` escapes the API surface.

All three formats expose the same operation and text surface; the current test suite exercises `Decimal.Format64`.

---

## Architecture

Single module. `import Decimals` re-exports the underlying `IEEE_754` and `Decimal_Primitives` modules, so the format types and their bit-level accessors are available through the one import.

| Type | Purpose |
|------|---------|
| `Decimal.Format32` / `.Format64` / `.Format128` | BID-encoded decimal values (from `Decimal_Primitives`, re-exported) |
| `Decimal.Operation` | Per-value accessor: `add`, `multiply`, `divide`, `fuse`, `compare`, `precedes` |
| `Decimal.Outcome` | Operation result: `value` + raised `status` flags |
| `Decimal.Context` | Precision, rounding, traps, clamping, tininess, exponent bounds |
| `Decimal.Status` / `Decimal.Flag` | IEEE exception flags as an `OptionSet` / enum |
| `Decimal.Text` | Per-value accessor: `render(into:style:)`, `render(appending:style:)` |
| `Decimal.Text.Parse` | Static parser: `Decimal.Format64.text(bytes)` |
| `Decimal.Text.Style` | `.plain`, `.scientific`, `.engineering` |
| `Decimal.Trap` | Typed error carrying the trapped flag, full status, and the computed value |

---

## Error Handling

Two throwing surfaces with distinct typed errors.

**Parsing** throws `Decimal.Text.Error`:

```
Decimal.Text.Error
├── .empty                 // Input was empty
├── .syntax(offset: Int)   // Invalid byte at offset
├── .high                  // Exponent above the context's maximum
└── .low                   // Exponent below the context's minimum
```

```swift
do {
    let price = try Decimal.Format64.text([UInt8]("19.99".utf8))
} catch .empty {
    // No input
} catch .syntax(let offset) {
    // Malformed at byte `offset`
} catch .high, .low {
    // Exponent outside the context's range
}
```

**Trapping** throws `Decimal.Trap<Value>`, which carries the flag that fired, the complete status set, and the value that was computed:

```swift
do {
    let quotient = try one.operation.divide(three).trapped(by: .inexact)
} catch {
    error.flag      // .inexact
    error.status    // full status set of the operation
    error.value     // the rounded result that would have been returned
}
```

---

## Related Packages

### Dependencies

- [swift-ieee-754](https://github.com/swift-ieee/swift-ieee-754) — IEEE 754 shared vocabulary this package builds on.
- swift-decimal-primitives (pre-release, `main` branch pin) — BID storage formats and bit-level encode/decode.
- swift-ascii-serializer-primitives (pre-release, `main` branch pin) — ASCII digit serialization used by text rendering.

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public flip.*
<!-- END: discussion -->

---

## License

Apache 2.0. See [LICENSE](LICENSE.md).
