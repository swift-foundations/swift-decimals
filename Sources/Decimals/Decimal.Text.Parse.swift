extension Decimal.Text.Parse where Value == Decimal.Format64 {
    /// Parse from contiguous bytes (canonical input substrate)
    public func callAsFunction(
        _ bytes: UnsafeBufferPointer<UInt8>,
        context: Decimal.Context = .format64
    ) throws(Decimal.Text.Error) -> Value {
        guard !bytes.isEmpty else {
            throw .empty
        }

        var index = 0

        // Parse optional sign
        var sign: Decimal.Sign = .positive
        if index < bytes.count {
            if bytes[index] == UInt8(ascii: "-") {
                sign = .negative
                index += 1
            } else if bytes[index] == UInt8(ascii: "+") {
                index += 1
            }
        }

        guard index < bytes.count else {
            throw .syntax(offset: index)
        }

        // Check for special values
        let remaining = bytes.count - index

        // Check for "Infinity" or "Inf"
        if remaining >= 3 {
            let i = bytes[index]
            let n = bytes[index + 1]
            let f = bytes[index + 2]
            if (i == UInt8(ascii: "I") || i == UInt8(ascii: "i")) && (n == UInt8(ascii: "n") || n == UInt8(ascii: "N")) && (f == UInt8(ascii: "f") || f == UInt8(ascii: "F")) {
                // Could be "Inf" or "Infinity"
                if remaining >= 8 {
                    // Check full "Infinity"
                    let rest = [bytes[index + 3], bytes[index + 4], bytes[index + 5], bytes[index + 6], bytes[index + 7]]
                    if (rest[0] == UInt8(ascii: "i") || rest[0] == UInt8(ascii: "I")) && (rest[1] == UInt8(ascii: "n") || rest[1] == UInt8(ascii: "N"))
                        && (rest[2] == UInt8(ascii: "i") || rest[2] == UInt8(ascii: "I")) && (rest[3] == UInt8(ascii: "t") || rest[3] == UInt8(ascii: "T"))
                        && (rest[4] == UInt8(ascii: "y") || rest[4] == UInt8(ascii: "Y"))
                    {
                        if index + 8 == bytes.count {
                            return .infinity(sign: sign)
                        }
                    }
                }
                if index + 3 == bytes.count {
                    return .infinity(sign: sign)
                }
            }
        }

        // Check for "NaN". Must be the entire remaining input — trailing bytes
        // after "NaN" are syntax errors, not silently accepted (F-005) — and the
        // parsed sign carries through to the NaN's sign bit instead of being
        // discarded (F-005).
        if remaining >= 3 {
            let n1 = bytes[index]
            let a = bytes[index + 1]
            let n2 = bytes[index + 2]
            if (n1 == UInt8(ascii: "N") || n1 == UInt8(ascii: "n")) && (a == UInt8(ascii: "a") || a == UInt8(ascii: "A")) && (n2 == UInt8(ascii: "N") || n2 == UInt8(ascii: "n")) {
                guard index + 3 == bytes.count else {
                    throw .syntax(offset: index + 3)
                }
                let nan = Value.nan()
                return sign == .negative ? nan.negated : nan
            }
        }

        // Parse numeric value
        var coefficient: UInt64 = 0
        var exponent: Int = 0
        var hasDigits = false
        var decimalPos: Int? = nil
        var digitCount = 0

        // Parse integer part and optional fractional part
        while index < bytes.count {
            let byte = bytes[index]

            if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                hasDigits = true
                let digit = UInt64(byte - UInt8(ascii: "0"))

                // Check for coefficient overflow
                if digitCount < 19 {  // UInt64 max is 20 digits
                    coefficient = coefficient * 10 + digit
                    digitCount += 1
                } else {
                    // Overflow - increment exponent
                    if decimalPos == nil {
                        exponent += 1
                    }
                }
                index += 1
            } else if byte == UInt8(ascii: ".") {
                if decimalPos != nil {
                    throw .syntax(offset: index)
                }
                decimalPos = digitCount
                index += 1
            } else {
                break
            }
        }

        guard hasDigits else {
            throw .syntax(offset: index)
        }

        // Adjust exponent for decimal point position
        if let dp = decimalPos {
            exponent -= (digitCount - dp)
        }

        // Parse optional exponent
        if index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "E") || byte == UInt8(ascii: "e") {
                index += 1

                guard index < bytes.count else {
                    throw .syntax(offset: index)
                }

                var expSign = 1
                if bytes[index] == UInt8(ascii: "-") {
                    expSign = -1
                    index += 1
                } else if bytes[index] == UInt8(ascii: "+") {
                    index += 1
                }

                guard index < bytes.count else {
                    throw .syntax(offset: index)
                }

                // Bound exponent-digit accumulation well below Int's range so an
                // arbitrarily long exponent-digit string (legal syntax, e.g. "E"
                // followed by dozens of digits) saturates a sentinel instead of
                // trapping via Int multiplication/addition overflow (F-005). The
                // sentinel is far beyond any format's maxExponent/minExponent, so
                // saturating it still correctly resolves to .high/.low below.
                let expSentinel = 1_000_000_000
                var expValue = 0
                var expTooLarge = false
                var hasExpDigits = false
                while index < bytes.count {
                    let b = bytes[index]
                    if b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") {
                        hasExpDigits = true
                        if expValue < expSentinel {
                            expValue = expValue * 10 + Int(b - UInt8(ascii: "0"))
                        } else {
                            expTooLarge = true
                        }
                        index += 1
                    } else {
                        break
                    }
                }

                guard hasExpDigits else {
                    throw .syntax(offset: index)
                }

                if expTooLarge {
                    throw expSign > 0 ? .high : .low
                }

                exponent += expSign * expValue
            }
        }

        // Check for trailing garbage
        guard index == bytes.count else {
            throw .syntax(offset: index)
        }

        // Handle zero
        if coefficient == 0 {
            return .zero(sign: sign)
        }

        // Round the parsed coefficient to the format's precision through the
        // shared rounding kernel before encoding. The digit-accumulation loop
        // above only guards against overflowing UInt64 itself (up to 19 digits),
        // which is far more than Format64's 16-digit precision; passing an
        // over-precision coefficient straight to encode() silently corrupts the
        // bit pattern instead of correctly rounding (F-005).
        let (roundedCoefficient, roundedExponent, _) = Decimals.Rounding.round(
            coefficient: UInt128(coefficient),
            exponent: Decimal.Exponent(exponent),
            sign: sign,
            rounding: context.rounding,
            precision: context.precision
        )

        // Check exponent bounds using the (possibly rounding-adjusted) exponent
        if roundedExponent > context.maxExponent {
            throw .high
        }
        if roundedExponent < context.minExponent {
            throw .low
        }

        return Value.encode(sign: sign, exponent: roundedExponent, coefficient: roundedCoefficient)
    }

    /// Parse from ArraySlice (common case)
    public func callAsFunction(
        _ bytes: ArraySlice<UInt8>,
        context: Decimal.Context = .format64
    ) throws(Decimal.Text.Error) -> Value {
        var result: Result<Value, Decimal.Text.Error>!
        bytes.withUnsafeBufferPointer { buffer in
            do {
                result = .success(try self(buffer, context: context))
            } catch let error as Decimal._TextError {
                result = .failure(error)
            } catch {
                fatalError("Unexpected error type")
            }
        }
        return try result.get()
    }

    /// Parse from Array (convenience)
    public func callAsFunction(
        _ bytes: [UInt8],
        context: Decimal.Context = .format64
    ) throws(Decimal.Text.Error) -> Value {
        var result: Result<Value, Decimal.Text.Error>!
        bytes.withUnsafeBufferPointer { buffer in
            do {
                result = .success(try self(buffer, context: context))
            } catch let error as Decimal._TextError {
                result = .failure(error)
            } catch {
                fatalError("Unexpected error type")
            }
        }
        return try result.get()
    }
}

// MARK: - Format32 Parsing

extension Decimal.Text.Parse where Value == Decimal.Format32 {
    /// Parse from contiguous bytes (canonical input substrate)
    public func callAsFunction(
        _ bytes: UnsafeBufferPointer<UInt8>,
        context: Decimal.Context = .format32
    ) throws(Decimal.Text.Error) -> Value {
        guard !bytes.isEmpty else {
            throw .empty
        }

        var index = 0

        // Parse optional sign
        var sign: Decimal.Sign = .positive
        if index < bytes.count {
            if bytes[index] == UInt8(ascii: "-") {
                sign = .negative
                index += 1
            } else if bytes[index] == UInt8(ascii: "+") {
                index += 1
            }
        }

        guard index < bytes.count else {
            throw .syntax(offset: index)
        }

        // Check for special values
        let remaining = bytes.count - index

        // Check for "Infinity" or "Inf"
        if remaining >= 3 {
            let i = bytes[index]
            let n = bytes[index + 1]
            let f = bytes[index + 2]
            if (i == UInt8(ascii: "I") || i == UInt8(ascii: "i")) && (n == UInt8(ascii: "n") || n == UInt8(ascii: "N")) && (f == UInt8(ascii: "f") || f == UInt8(ascii: "F")) {
                if remaining >= 8 {
                    let rest = [bytes[index + 3], bytes[index + 4], bytes[index + 5], bytes[index + 6], bytes[index + 7]]
                    if (rest[0] == UInt8(ascii: "i") || rest[0] == UInt8(ascii: "I")) && (rest[1] == UInt8(ascii: "n") || rest[1] == UInt8(ascii: "N"))
                        && (rest[2] == UInt8(ascii: "i") || rest[2] == UInt8(ascii: "I")) && (rest[3] == UInt8(ascii: "t") || rest[3] == UInt8(ascii: "T"))
                        && (rest[4] == UInt8(ascii: "y") || rest[4] == UInt8(ascii: "Y"))
                    {
                        if index + 8 == bytes.count {
                            return .infinity(sign: sign)
                        }
                    }
                }
                if index + 3 == bytes.count {
                    return .infinity(sign: sign)
                }
            }
        }

        // Check for "NaN". Must be the entire remaining input — trailing bytes
        // after "NaN" are syntax errors, not silently accepted (F-005) — and the
        // parsed sign carries through to the NaN's sign bit instead of being
        // discarded (F-005).
        if remaining >= 3 {
            let n1 = bytes[index]
            let a = bytes[index + 1]
            let n2 = bytes[index + 2]
            if (n1 == UInt8(ascii: "N") || n1 == UInt8(ascii: "n")) && (a == UInt8(ascii: "a") || a == UInt8(ascii: "A")) && (n2 == UInt8(ascii: "N") || n2 == UInt8(ascii: "n")) {
                guard index + 3 == bytes.count else {
                    throw .syntax(offset: index + 3)
                }
                let nan = Value.nan()
                return sign == .negative ? nan.negated : nan
            }
        }

        // Parse numeric value
        var coefficient: UInt32 = 0
        var exponent: Int = 0
        var hasDigits = false
        var decimalPos: Int? = nil
        var digitCount = 0

        while index < bytes.count {
            let byte = bytes[index]

            if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                hasDigits = true
                let digit = UInt32(byte - UInt8(ascii: "0"))

                if digitCount < 9 {  // UInt32 max is 10 digits, but we need headroom
                    coefficient = coefficient * 10 + digit
                    digitCount += 1
                } else {
                    if decimalPos == nil {
                        exponent += 1
                    }
                }
                index += 1
            } else if byte == UInt8(ascii: ".") {
                if decimalPos != nil {
                    throw .syntax(offset: index)
                }
                decimalPos = digitCount
                index += 1
            } else {
                break
            }
        }

        guard hasDigits else {
            throw .syntax(offset: index)
        }

        if let dp = decimalPos {
            exponent -= (digitCount - dp)
        }

        // Parse optional exponent
        if index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "E") || byte == UInt8(ascii: "e") {
                index += 1

                guard index < bytes.count else {
                    throw .syntax(offset: index)
                }

                var expSign = 1
                if bytes[index] == UInt8(ascii: "-") {
                    expSign = -1
                    index += 1
                } else if bytes[index] == UInt8(ascii: "+") {
                    index += 1
                }

                guard index < bytes.count else {
                    throw .syntax(offset: index)
                }

                // Bound exponent-digit accumulation well below Int's range so an
                // arbitrarily long exponent-digit string (legal syntax, e.g. "E"
                // followed by dozens of digits) saturates a sentinel instead of
                // trapping via Int multiplication/addition overflow (F-005). The
                // sentinel is far beyond any format's maxExponent/minExponent, so
                // saturating it still correctly resolves to .high/.low below.
                let expSentinel = 1_000_000_000
                var expValue = 0
                var expTooLarge = false
                var hasExpDigits = false
                while index < bytes.count {
                    let b = bytes[index]
                    if b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") {
                        hasExpDigits = true
                        if expValue < expSentinel {
                            expValue = expValue * 10 + Int(b - UInt8(ascii: "0"))
                        } else {
                            expTooLarge = true
                        }
                        index += 1
                    } else {
                        break
                    }
                }

                guard hasExpDigits else {
                    throw .syntax(offset: index)
                }

                if expTooLarge {
                    throw expSign > 0 ? .high : .low
                }

                exponent += expSign * expValue
            }
        }

        guard index == bytes.count else {
            throw .syntax(offset: index)
        }

        if coefficient == 0 {
            return .zero(sign: sign)
        }

        // Round the parsed coefficient to the format's precision through the
        // shared rounding kernel before encoding. The digit-accumulation loop
        // above only guards against overflowing UInt32 itself (up to 9 digits),
        // which is more than Format32's 7-digit precision; passing an
        // over-precision coefficient straight to encode() silently corrupts the
        // bit pattern instead of correctly rounding (F-005).
        let (roundedCoefficient, roundedExponent, _) = Decimals.Rounding.round(
            coefficient: UInt64(coefficient),
            exponent: Decimal.Exponent(exponent),
            sign: sign,
            rounding: context.rounding,
            precision: context.precision
        )

        // Check exponent bounds using the (possibly rounding-adjusted) exponent
        if roundedExponent > context.maxExponent {
            throw .high
        }
        if roundedExponent < context.minExponent {
            throw .low
        }

        return Value.encode(sign: sign, exponent: roundedExponent, coefficient: roundedCoefficient)
    }

    /// Parse from ArraySlice (common case)
    public func callAsFunction(
        _ bytes: ArraySlice<UInt8>,
        context: Decimal.Context = .format32
    ) throws(Decimal.Text.Error) -> Value {
        var result: Result<Value, Decimal.Text.Error>!
        bytes.withUnsafeBufferPointer { buffer in
            do {
                result = .success(try self(buffer, context: context))
            } catch let error as Decimal._TextError {
                result = .failure(error)
            } catch {
                fatalError("Unexpected error type")
            }
        }
        return try result.get()
    }

    /// Parse from Array (convenience)
    public func callAsFunction(
        _ bytes: [UInt8],
        context: Decimal.Context = .format32
    ) throws(Decimal.Text.Error) -> Value {
        var result: Result<Value, Decimal.Text.Error>!
        bytes.withUnsafeBufferPointer { buffer in
            do {
                result = .success(try self(buffer, context: context))
            } catch let error as Decimal._TextError {
                result = .failure(error)
            } catch {
                fatalError("Unexpected error type")
            }
        }
        return try result.get()
    }
}

// MARK: - Format128 Parsing

extension Decimal.Text.Parse where Value == Decimal.Format128 {
    /// Parse from contiguous bytes (canonical input substrate)
    public func callAsFunction(
        _ bytes: UnsafeBufferPointer<UInt8>,
        context: Decimal.Context = .format128
    ) throws(Decimal.Text.Error) -> Value {
        guard !bytes.isEmpty else {
            throw .empty
        }

        var index = 0

        // Parse optional sign
        var sign: Decimal.Sign = .positive
        if index < bytes.count {
            if bytes[index] == UInt8(ascii: "-") {
                sign = .negative
                index += 1
            } else if bytes[index] == UInt8(ascii: "+") {
                index += 1
            }
        }

        guard index < bytes.count else {
            throw .syntax(offset: index)
        }

        // Check for special values
        let remaining = bytes.count - index

        // Check for "Infinity" or "Inf"
        if remaining >= 3 {
            let i = bytes[index]
            let n = bytes[index + 1]
            let f = bytes[index + 2]
            if (i == UInt8(ascii: "I") || i == UInt8(ascii: "i")) && (n == UInt8(ascii: "n") || n == UInt8(ascii: "N")) && (f == UInt8(ascii: "f") || f == UInt8(ascii: "F")) {
                if remaining >= 8 {
                    let rest = [bytes[index + 3], bytes[index + 4], bytes[index + 5], bytes[index + 6], bytes[index + 7]]
                    if (rest[0] == UInt8(ascii: "i") || rest[0] == UInt8(ascii: "I")) && (rest[1] == UInt8(ascii: "n") || rest[1] == UInt8(ascii: "N"))
                        && (rest[2] == UInt8(ascii: "i") || rest[2] == UInt8(ascii: "I")) && (rest[3] == UInt8(ascii: "t") || rest[3] == UInt8(ascii: "T"))
                        && (rest[4] == UInt8(ascii: "y") || rest[4] == UInt8(ascii: "Y"))
                    {
                        if index + 8 == bytes.count {
                            return .infinity(sign: sign)
                        }
                    }
                }
                if index + 3 == bytes.count {
                    return .infinity(sign: sign)
                }
            }
        }

        // Check for "NaN". Must be the entire remaining input — trailing bytes
        // after "NaN" are syntax errors, not silently accepted (F-005) — and the
        // parsed sign carries through to the NaN's sign bit instead of being
        // discarded (F-005).
        if remaining >= 3 {
            let n1 = bytes[index]
            let a = bytes[index + 1]
            let n2 = bytes[index + 2]
            if (n1 == UInt8(ascii: "N") || n1 == UInt8(ascii: "n")) && (a == UInt8(ascii: "a") || a == UInt8(ascii: "A")) && (n2 == UInt8(ascii: "N") || n2 == UInt8(ascii: "n")) {
                guard index + 3 == bytes.count else {
                    throw .syntax(offset: index + 3)
                }
                let nan = Value.nan()
                return sign == .negative ? nan.negated : nan
            }
        }

        // Parse numeric value
        var coefficient: UInt128 = 0
        var exponent: Int = 0
        var hasDigits = false
        var decimalPos: Int? = nil
        var digitCount = 0

        while index < bytes.count {
            let byte = bytes[index]

            if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                hasDigits = true
                let digit = UInt128(byte - UInt8(ascii: "0"))

                if digitCount < 38 {  // UInt128 max is 39 digits
                    coefficient = coefficient * 10 + digit
                    digitCount += 1
                } else {
                    if decimalPos == nil {
                        exponent += 1
                    }
                }
                index += 1
            } else if byte == UInt8(ascii: ".") {
                if decimalPos != nil {
                    throw .syntax(offset: index)
                }
                decimalPos = digitCount
                index += 1
            } else {
                break
            }
        }

        guard hasDigits else {
            throw .syntax(offset: index)
        }

        if let dp = decimalPos {
            exponent -= (digitCount - dp)
        }

        // Parse optional exponent
        if index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "E") || byte == UInt8(ascii: "e") {
                index += 1

                guard index < bytes.count else {
                    throw .syntax(offset: index)
                }

                var expSign = 1
                if bytes[index] == UInt8(ascii: "-") {
                    expSign = -1
                    index += 1
                } else if bytes[index] == UInt8(ascii: "+") {
                    index += 1
                }

                guard index < bytes.count else {
                    throw .syntax(offset: index)
                }

                // Bound exponent-digit accumulation well below Int's range so an
                // arbitrarily long exponent-digit string (legal syntax, e.g. "E"
                // followed by dozens of digits) saturates a sentinel instead of
                // trapping via Int multiplication/addition overflow (F-005). The
                // sentinel is far beyond any format's maxExponent/minExponent, so
                // saturating it still correctly resolves to .high/.low below.
                let expSentinel = 1_000_000_000
                var expValue = 0
                var expTooLarge = false
                var hasExpDigits = false
                while index < bytes.count {
                    let b = bytes[index]
                    if b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") {
                        hasExpDigits = true
                        if expValue < expSentinel {
                            expValue = expValue * 10 + Int(b - UInt8(ascii: "0"))
                        } else {
                            expTooLarge = true
                        }
                        index += 1
                    } else {
                        break
                    }
                }

                guard hasExpDigits else {
                    throw .syntax(offset: index)
                }

                if expTooLarge {
                    throw expSign > 0 ? .high : .low
                }

                exponent += expSign * expValue
            }
        }

        guard index == bytes.count else {
            throw .syntax(offset: index)
        }

        if coefficient == 0 {
            return .zero(sign: sign)
        }

        // Round the parsed coefficient to the format's precision through the
        // shared rounding kernel before encoding. The digit-accumulation loop
        // above only guards against overflowing UInt128 itself (up to 38 digits),
        // which is more than Format128's 34-digit precision; passing an
        // over-precision coefficient straight to encode() silently corrupts the
        // bit pattern instead of correctly rounding (F-005).
        let (roundedCoefficient, roundedExponent, _) = Decimals.Rounding.round128(
            coefficient: coefficient,
            exponent: Decimal.Exponent(exponent),
            sign: sign,
            rounding: context.rounding,
            precision: context.precision
        )

        // Check exponent bounds using the (possibly rounding-adjusted) exponent
        if roundedExponent > context.maxExponent {
            throw .high
        }
        if roundedExponent < context.minExponent {
            throw .low
        }

        return Value.encode(sign: sign, exponent: roundedExponent, coefficient: roundedCoefficient)
    }

    /// Parse from ArraySlice (common case)
    public func callAsFunction(
        _ bytes: ArraySlice<UInt8>,
        context: Decimal.Context = .format128
    ) throws(Decimal.Text.Error) -> Value {
        var result: Result<Value, Decimal.Text.Error>!
        bytes.withUnsafeBufferPointer { buffer in
            do {
                result = .success(try self(buffer, context: context))
            } catch let error as Decimal._TextError {
                result = .failure(error)
            } catch {
                fatalError("Unexpected error type")
            }
        }
        return try result.get()
    }

    /// Parse from Array (convenience)
    public func callAsFunction(
        _ bytes: [UInt8],
        context: Decimal.Context = .format128
    ) throws(Decimal.Text.Error) -> Value {
        var result: Result<Value, Decimal.Text.Error>!
        bytes.withUnsafeBufferPointer { buffer in
            do {
                result = .success(try self(buffer, context: context))
            } catch let error as Decimal._TextError {
                result = .failure(error)
            } catch {
                fatalError("Unexpected error type")
            }
        }
        return try result.get()
    }
}
