internal import ASCII_Decimal_Serializer_Primitives

// MARK: - Format64 Rendering

extension Decimal.Text where Value == Decimal.Format64 {
    /// Render into preallocated buffer, returns bytes written
    ///
    /// - Precondition: `buffer.count` must be at least `requiredCapacity(style:)` for
    ///   this value and `style`. Callers that size their own buffers must query
    ///   `requiredCapacity(style:)` first; `render(appending:)` does this automatically.
    public func render(
        into buffer: UnsafeMutableBufferPointer<UInt8>,
        style: Decimal.Text.Style = .plain
    ) -> Int {
        let capacity = requiredCapacity(style: style)
        precondition(
            buffer.count >= capacity,
            "Decimal.Text.render(into:): buffer has \(buffer.count) bytes but this value needs at least \(capacity) bytes for style \(style)."
        )

        var offset = 0

        // Handle sign
        if base.sign == .negative {
            buffer[offset] = UInt8(ascii: "-")
            offset += 1
        }

        // Handle special values
        if base.test.nan {
            let nan: [UInt8] = [UInt8(ascii: "N"), UInt8(ascii: "a"), UInt8(ascii: "N")]
            for byte in nan {
                buffer[offset] = byte
                offset += 1
            }
            return offset
        }

        if base.test.infinite {
            let inf: [UInt8] = [UInt8(ascii: "I"), UInt8(ascii: "n"), UInt8(ascii: "f"), UInt8(ascii: "i"), UInt8(ascii: "n"), UInt8(ascii: "i"), UInt8(ascii: "t"), UInt8(ascii: "y")]
            for byte in inf {
                buffer[offset] = byte
                offset += 1
            }
            return offset
        }

        // Handle zero
        if base.test.zero {
            buffer[offset] = UInt8(ascii: "0")
            return offset + 1
        }

        // Extract coefficient and exponent
        let coefficient = base.extractCoefficient()
        let exponent = base.extractExponent()

        // Convert coefficient to digits (delegated to L1 ASCII decimal serializer)
        var digitCodes: [ASCII.Code] = []
        ASCII.Decimal.Serializer().serialize(coefficient, into: &digitCodes)
        let digits: [UInt8] = digitCodes.map(\.underlying)

        let numDigits = digits.count
        let adjustedExponent = exponent.rawValue + numDigits - 1

        switch style {
        case .plain:
            // Plain format: no exponent unless necessary
            if exponent.rawValue >= 0 {
                // Integer or integer with trailing zeros
                for digit in digits {
                    buffer[offset] = digit
                    offset += 1
                }
                for _ in 0..<exponent.rawValue {
                    buffer[offset] = UInt8(ascii: "0")
                    offset += 1
                }
            } else if exponent.rawValue >= -numDigits + 1 {
                // Decimal point within digits
                let decimalPos = numDigits + exponent.rawValue
                for (i, digit) in digits.enumerated() {
                    if i == decimalPos {
                        buffer[offset] = UInt8(ascii: ".")
                        offset += 1
                    }
                    buffer[offset] = digit
                    offset += 1
                }
            } else {
                // Need leading zeros after decimal
                buffer[offset] = UInt8(ascii: "0")
                offset += 1
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for _ in 0..<(-exponent.rawValue - numDigits) {
                    buffer[offset] = UInt8(ascii: "0")
                    offset += 1
                }
                for digit in digits {
                    buffer[offset] = digit
                    offset += 1
                }
            }

        case .scientific:
            // Scientific: d.dddE+ee
            buffer[offset] = digits[0]
            offset += 1
            if numDigits > 1 {
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for i in 1..<numDigits {
                    buffer[offset] = digits[i]
                    offset += 1
                }
            }
            buffer[offset] = UInt8(ascii: "E")
            offset += 1
            offset += writeExponent(adjustedExponent, to: buffer, at: offset)

        case .engineering:
            // Engineering: exponent multiple of 3
            let engExp = (adjustedExponent / 3) * 3
            let shift = adjustedExponent - engExp
            let intDigits = shift + 1

            for i in 0..<intDigits {
                if i < numDigits {
                    buffer[offset] = digits[i]
                } else {
                    buffer[offset] = UInt8(ascii: "0")
                }
                offset += 1
            }
            if intDigits < numDigits {
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for i in intDigits..<numDigits {
                    buffer[offset] = digits[i]
                    offset += 1
                }
            }
            if engExp != 0 {
                buffer[offset] = UInt8(ascii: "E")
                offset += 1
                offset += writeExponent(engExp, to: buffer, at: offset)
            }
        }

        return offset
    }

    @usableFromInline
    internal func writeExponent(_ exp: Int, to buffer: UnsafeMutableBufferPointer<UInt8>, at offset: Int) -> Int {
        var off = offset
        if exp >= 0 {
            buffer[off] = UInt8(ascii: "+")
        } else {
            buffer[off] = UInt8(ascii: "-")
        }
        off += 1

        let absExp = abs(exp)
        var expDigits: [UInt8] = []
        var temp = absExp
        if temp == 0 {
            expDigits.append(UInt8(ascii: "0"))
        }
        while temp > 0 {
            expDigits.append(UInt8(ascii: "0") + UInt8(temp % 10))
            temp /= 10
        }
        expDigits.reverse()
        for digit in expDigits {
            buffer[off] = digit
            off += 1
        }
        return off - offset
    }

    /// Render by appending to byte array
    public func render(
        appending buffer: inout [UInt8],
        style: Decimal.Text.Style = .plain
    ) {
        // Size the scratch buffer exactly to what this value/style needs; a fixed
        // 64-byte buffer is not large enough for large-magnitude exponents in
        // `.plain` style (F-001).
        var temp = [UInt8](repeating: 0, count: requiredCapacity(style: style))
        let count = temp.withUnsafeMutableBufferPointer { ptr in
            render(into: ptr, style: style)
        }
        buffer.append(contentsOf: temp[0..<count])
    }

    /// The number of bytes `render(into:style:)` may write for this value and `style`.
    ///
    /// `render(into:style:)` traps via precondition if the supplied buffer is
    /// smaller than this. This is a safe (possibly slightly generous) upper bound,
    /// not necessarily the exact byte count written.
    public func requiredCapacity(style: Decimal.Text.Style = .plain) -> Int {
        if base.test.nan {
            return 4  // sign + "NaN"
        }
        if base.test.infinite {
            return 9  // sign + "Infinity"
        }
        if base.test.zero {
            return 2  // sign + "0"
        }

        let coefficient = base.extractCoefficient()
        let exponent = base.extractExponent()
        var digitCodes: [ASCII.Code] = []
        ASCII.Decimal.Serializer().serialize(coefficient, into: &digitCodes)

        return Self.requiredCapacity(numDigits: digitCodes.count, exponent: exponent.rawValue, style: style)
    }

    /// Safe upper bound on rendered byte length given a digit count and exponent, for `style`.
    @usableFromInline
    internal static func requiredCapacity(numDigits: Int, exponent: Int, style: Decimal.Text.Style) -> Int {
        let adjustedExponent = exponent + numDigits - 1
        // Bounds the plain-style leading/trailing zero run (see F-001 analysis:
        // trailing-zero count is `exponent` when >= 0, leading-zero count is at
        // most `-exponent` when < 0).
        let zeroRun = max(exponent, -exponent)
        let exponentDigits = decimalDigitCount(adjustedExponent)

        switch style {
        case .plain:
            // sign + "0." lead-in + digits + decimal point + zero run
            return 1 + 2 + numDigits + 1 + zeroRun
        case .scientific:
            // sign + first digit + decimal point + remaining digits + "E" + exponent sign + exponent digits
            return 1 + 1 + 1 + numDigits + 1 + 1 + exponentDigits
        case .engineering:
            // sign + up to 3 padded integer digits + decimal point + remaining digits + "E" + exponent sign + exponent digits
            return 1 + 3 + 1 + numDigits + 1 + 1 + exponentDigits
        }
    }

    /// Number of base-10 digits needed to render `abs(value)` (minimum 1, matching `writeExponent`).
    @usableFromInline
    internal static func decimalDigitCount(_ value: Int) -> Int {
        var count = 1
        var remainder = value.magnitude / 10
        while remainder > 0 {
            count += 1
            remainder /= 10
        }
        return count
    }
}

// MARK: - Format32 Rendering

extension Decimal.Text where Value == Decimal.Format32 {
    /// Render into preallocated buffer, returns bytes written
    ///
    /// - Precondition: `buffer.count` must be at least `requiredCapacity(style:)` for
    ///   this value and `style`. Callers that size their own buffers must query
    ///   `requiredCapacity(style:)` first; `render(appending:)` does this automatically.
    public func render(
        into buffer: UnsafeMutableBufferPointer<UInt8>,
        style: Decimal.Text.Style = .plain
    ) -> Int {
        let capacity = requiredCapacity(style: style)
        precondition(
            buffer.count >= capacity,
            "Decimal.Text.render(into:): buffer has \(buffer.count) bytes but this value needs at least \(capacity) bytes for style \(style)."
        )

        var offset = 0

        // Handle sign
        if base.sign == .negative {
            buffer[offset] = UInt8(ascii: "-")
            offset += 1
        }

        // Handle special values
        if base.test.nan {
            let nan: [UInt8] = [UInt8(ascii: "N"), UInt8(ascii: "a"), UInt8(ascii: "N")]
            for byte in nan {
                buffer[offset] = byte
                offset += 1
            }
            return offset
        }

        if base.test.infinite {
            let inf: [UInt8] = [UInt8(ascii: "I"), UInt8(ascii: "n"), UInt8(ascii: "f"), UInt8(ascii: "i"), UInt8(ascii: "n"), UInt8(ascii: "i"), UInt8(ascii: "t"), UInt8(ascii: "y")]
            for byte in inf {
                buffer[offset] = byte
                offset += 1
            }
            return offset
        }

        // Handle zero
        if base.test.zero {
            buffer[offset] = UInt8(ascii: "0")
            return offset + 1
        }

        // Extract coefficient and exponent
        let coefficient = base.extractCoefficient()
        let exponent = base.extractExponent()

        // Convert coefficient to digits (delegated to L1 ASCII decimal serializer)
        var digitCodes: [ASCII.Code] = []
        ASCII.Decimal.Serializer().serialize(coefficient, into: &digitCodes)
        let digits: [UInt8] = digitCodes.map(\.underlying)

        let numDigits = digits.count
        let adjustedExponent = exponent.rawValue + numDigits - 1

        switch style {
        case .plain:
            if exponent.rawValue >= 0 {
                for digit in digits {
                    buffer[offset] = digit
                    offset += 1
                }
                for _ in 0..<exponent.rawValue {
                    buffer[offset] = UInt8(ascii: "0")
                    offset += 1
                }
            } else if exponent.rawValue >= -numDigits + 1 {
                let decimalPos = numDigits + exponent.rawValue
                for (i, digit) in digits.enumerated() {
                    if i == decimalPos {
                        buffer[offset] = UInt8(ascii: ".")
                        offset += 1
                    }
                    buffer[offset] = digit
                    offset += 1
                }
            } else {
                buffer[offset] = UInt8(ascii: "0")
                offset += 1
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for _ in 0..<(-exponent.rawValue - numDigits) {
                    buffer[offset] = UInt8(ascii: "0")
                    offset += 1
                }
                for digit in digits {
                    buffer[offset] = digit
                    offset += 1
                }
            }

        case .scientific:
            buffer[offset] = digits[0]
            offset += 1
            if numDigits > 1 {
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for i in 1..<numDigits {
                    buffer[offset] = digits[i]
                    offset += 1
                }
            }
            buffer[offset] = UInt8(ascii: "E")
            offset += 1
            offset += writeExponent(adjustedExponent, to: buffer, at: offset)

        case .engineering:
            let engExp = (adjustedExponent / 3) * 3
            let shift = adjustedExponent - engExp
            let intDigits = shift + 1

            for i in 0..<intDigits {
                if i < numDigits {
                    buffer[offset] = digits[i]
                } else {
                    buffer[offset] = UInt8(ascii: "0")
                }
                offset += 1
            }
            if intDigits < numDigits {
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for i in intDigits..<numDigits {
                    buffer[offset] = digits[i]
                    offset += 1
                }
            }
            if engExp != 0 {
                buffer[offset] = UInt8(ascii: "E")
                offset += 1
                offset += writeExponent(engExp, to: buffer, at: offset)
            }
        }

        return offset
    }

    @usableFromInline
    internal func writeExponent(_ exp: Int, to buffer: UnsafeMutableBufferPointer<UInt8>, at offset: Int) -> Int {
        var off = offset
        if exp >= 0 {
            buffer[off] = UInt8(ascii: "+")
        } else {
            buffer[off] = UInt8(ascii: "-")
        }
        off += 1

        let absExp = abs(exp)
        var expDigits: [UInt8] = []
        var temp = absExp
        if temp == 0 {
            expDigits.append(UInt8(ascii: "0"))
        }
        while temp > 0 {
            expDigits.append(UInt8(ascii: "0") + UInt8(temp % 10))
            temp /= 10
        }
        expDigits.reverse()
        for digit in expDigits {
            buffer[off] = digit
            off += 1
        }
        return off - offset
    }

    /// Render by appending to byte array
    public func render(
        appending buffer: inout [UInt8],
        style: Decimal.Text.Style = .plain
    ) {
        // Size the scratch buffer exactly to what this value/style needs; a fixed
        // 32-byte buffer is not large enough for large-magnitude exponents in
        // `.plain` style (F-001).
        var temp = [UInt8](repeating: 0, count: requiredCapacity(style: style))
        let count = temp.withUnsafeMutableBufferPointer { ptr in
            render(into: ptr, style: style)
        }
        buffer.append(contentsOf: temp[0..<count])
    }

    /// The number of bytes `render(into:style:)` may write for this value and `style`.
    ///
    /// `render(into:style:)` traps via precondition if the supplied buffer is
    /// smaller than this. This is a safe (possibly slightly generous) upper bound,
    /// not necessarily the exact byte count written.
    public func requiredCapacity(style: Decimal.Text.Style = .plain) -> Int {
        if base.test.nan {
            return 4  // sign + "NaN"
        }
        if base.test.infinite {
            return 9  // sign + "Infinity"
        }
        if base.test.zero {
            return 2  // sign + "0"
        }

        let coefficient = base.extractCoefficient()
        let exponent = base.extractExponent()
        var digitCodes: [ASCII.Code] = []
        ASCII.Decimal.Serializer().serialize(coefficient, into: &digitCodes)

        return Self.requiredCapacity(numDigits: digitCodes.count, exponent: exponent.rawValue, style: style)
    }

    /// Safe upper bound on rendered byte length given a digit count and exponent, for `style`.
    @usableFromInline
    internal static func requiredCapacity(numDigits: Int, exponent: Int, style: Decimal.Text.Style) -> Int {
        let adjustedExponent = exponent + numDigits - 1
        let zeroRun = max(exponent, -exponent)
        let exponentDigits = decimalDigitCount(adjustedExponent)

        switch style {
        case .plain:
            return 1 + 2 + numDigits + 1 + zeroRun
        case .scientific:
            return 1 + 1 + 1 + numDigits + 1 + 1 + exponentDigits
        case .engineering:
            return 1 + 3 + 1 + numDigits + 1 + 1 + exponentDigits
        }
    }

    /// Number of base-10 digits needed to render `abs(value)` (minimum 1, matching `writeExponent`).
    @usableFromInline
    internal static func decimalDigitCount(_ value: Int) -> Int {
        var count = 1
        var remainder = value.magnitude / 10
        while remainder > 0 {
            count += 1
            remainder /= 10
        }
        return count
    }
}

// MARK: - Format128 Rendering

extension Decimal.Text where Value == Decimal.Format128 {
    /// Render into preallocated buffer, returns bytes written
    ///
    /// - Precondition: `buffer.count` must be at least `requiredCapacity(style:)` for
    ///   this value and `style`. Callers that size their own buffers must query
    ///   `requiredCapacity(style:)` first; `render(appending:)` does this automatically.
    public func render(
        into buffer: UnsafeMutableBufferPointer<UInt8>,
        style: Decimal.Text.Style = .plain
    ) -> Int {
        let capacity = requiredCapacity(style: style)
        precondition(
            buffer.count >= capacity,
            "Decimal.Text.render(into:): buffer has \(buffer.count) bytes but this value needs at least \(capacity) bytes for style \(style)."
        )

        var offset = 0

        // Handle sign
        if base.sign == .negative {
            buffer[offset] = UInt8(ascii: "-")
            offset += 1
        }

        // Handle special values
        if base.test.nan {
            let nan: [UInt8] = [UInt8(ascii: "N"), UInt8(ascii: "a"), UInt8(ascii: "N")]
            for byte in nan {
                buffer[offset] = byte
                offset += 1
            }
            return offset
        }

        if base.test.infinite {
            let inf: [UInt8] = [UInt8(ascii: "I"), UInt8(ascii: "n"), UInt8(ascii: "f"), UInt8(ascii: "i"), UInt8(ascii: "n"), UInt8(ascii: "i"), UInt8(ascii: "t"), UInt8(ascii: "y")]
            for byte in inf {
                buffer[offset] = byte
                offset += 1
            }
            return offset
        }

        // Handle zero
        if base.test.zero {
            buffer[offset] = UInt8(ascii: "0")
            return offset + 1
        }

        // Extract coefficient and exponent
        let coefficient = base.extractCoefficient()
        let exponent = base.extractExponent()

        // Convert coefficient to digits (delegated to L1 ASCII decimal serializer)
        var digitCodes: [ASCII.Code] = []
        ASCII.Decimal.Serializer().serialize(coefficient, into: &digitCodes)
        let digits: [UInt8] = digitCodes.map(\.underlying)

        let numDigits = digits.count
        let adjustedExponent = exponent.rawValue + numDigits - 1

        switch style {
        case .plain:
            if exponent.rawValue >= 0 {
                for digit in digits {
                    buffer[offset] = digit
                    offset += 1
                }
                for _ in 0..<exponent.rawValue {
                    buffer[offset] = UInt8(ascii: "0")
                    offset += 1
                }
            } else if exponent.rawValue >= -numDigits + 1 {
                let decimalPos = numDigits + exponent.rawValue
                for (i, digit) in digits.enumerated() {
                    if i == decimalPos {
                        buffer[offset] = UInt8(ascii: ".")
                        offset += 1
                    }
                    buffer[offset] = digit
                    offset += 1
                }
            } else {
                buffer[offset] = UInt8(ascii: "0")
                offset += 1
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for _ in 0..<(-exponent.rawValue - numDigits) {
                    buffer[offset] = UInt8(ascii: "0")
                    offset += 1
                }
                for digit in digits {
                    buffer[offset] = digit
                    offset += 1
                }
            }

        case .scientific:
            buffer[offset] = digits[0]
            offset += 1
            if numDigits > 1 {
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for i in 1..<numDigits {
                    buffer[offset] = digits[i]
                    offset += 1
                }
            }
            buffer[offset] = UInt8(ascii: "E")
            offset += 1
            offset += writeExponent(adjustedExponent, to: buffer, at: offset)

        case .engineering:
            let engExp = (adjustedExponent / 3) * 3
            let shift = adjustedExponent - engExp
            let intDigits = shift + 1

            for i in 0..<intDigits {
                if i < numDigits {
                    buffer[offset] = digits[i]
                } else {
                    buffer[offset] = UInt8(ascii: "0")
                }
                offset += 1
            }
            if intDigits < numDigits {
                buffer[offset] = UInt8(ascii: ".")
                offset += 1
                for i in intDigits..<numDigits {
                    buffer[offset] = digits[i]
                    offset += 1
                }
            }
            if engExp != 0 {
                buffer[offset] = UInt8(ascii: "E")
                offset += 1
                offset += writeExponent(engExp, to: buffer, at: offset)
            }
        }

        return offset
    }

    @usableFromInline
    internal func writeExponent(_ exp: Int, to buffer: UnsafeMutableBufferPointer<UInt8>, at offset: Int) -> Int {
        var off = offset
        if exp >= 0 {
            buffer[off] = UInt8(ascii: "+")
        } else {
            buffer[off] = UInt8(ascii: "-")
        }
        off += 1

        let absExp = abs(exp)
        var expDigits: [UInt8] = []
        var temp = absExp
        if temp == 0 {
            expDigits.append(UInt8(ascii: "0"))
        }
        while temp > 0 {
            expDigits.append(UInt8(ascii: "0") + UInt8(temp % 10))
            temp /= 10
        }
        expDigits.reverse()
        for digit in expDigits {
            buffer[off] = digit
            off += 1
        }
        return off - offset
    }

    /// Render by appending to byte array
    public func render(
        appending buffer: inout [UInt8],
        style: Decimal.Text.Style = .plain
    ) {
        // Size the scratch buffer exactly to what this value/style needs; a fixed
        // 64-byte buffer is not large enough for large-magnitude exponents in
        // `.plain` style (F-001) — Format128's exponent range reaches +6144/-6143.
        var temp = [UInt8](repeating: 0, count: requiredCapacity(style: style))
        let count = temp.withUnsafeMutableBufferPointer { ptr in
            render(into: ptr, style: style)
        }
        buffer.append(contentsOf: temp[0..<count])
    }

    /// The number of bytes `render(into:style:)` may write for this value and `style`.
    ///
    /// `render(into:style:)` traps via precondition if the supplied buffer is
    /// smaller than this. This is a safe (possibly slightly generous) upper bound,
    /// not necessarily the exact byte count written.
    public func requiredCapacity(style: Decimal.Text.Style = .plain) -> Int {
        if base.test.nan {
            return 4  // sign + "NaN"
        }
        if base.test.infinite {
            return 9  // sign + "Infinity"
        }
        if base.test.zero {
            return 2  // sign + "0"
        }

        let coefficient = base.extractCoefficient()
        let exponent = base.extractExponent()
        var digitCodes: [ASCII.Code] = []
        ASCII.Decimal.Serializer().serialize(coefficient, into: &digitCodes)

        return Self.requiredCapacity(numDigits: digitCodes.count, exponent: exponent.rawValue, style: style)
    }

    /// Safe upper bound on rendered byte length given a digit count and exponent, for `style`.
    @usableFromInline
    internal static func requiredCapacity(numDigits: Int, exponent: Int, style: Decimal.Text.Style) -> Int {
        let adjustedExponent = exponent + numDigits - 1
        let zeroRun = max(exponent, -exponent)
        let exponentDigits = decimalDigitCount(adjustedExponent)

        switch style {
        case .plain:
            return 1 + 2 + numDigits + 1 + zeroRun
        case .scientific:
            return 1 + 1 + 1 + numDigits + 1 + 1 + exponentDigits
        case .engineering:
            return 1 + 3 + 1 + numDigits + 1 + 1 + exponentDigits
        }
    }

    /// Number of base-10 digits needed to render `abs(value)` (minimum 1, matching `writeExponent`).
    @usableFromInline
    internal static func decimalDigitCount(_ value: Int) -> Int {
        var count = 1
        var remainder = value.magnitude / 10
        while remainder > 0 {
            count += 1
            remainder /= 10
        }
        return count
    }
}
