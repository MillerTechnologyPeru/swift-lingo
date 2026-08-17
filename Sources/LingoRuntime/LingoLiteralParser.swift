/// Reads a Lingo literal back out of its source spelling — the job of
/// `value("[#a: 1, \"b\"]")`, and of the score's behavior initializers,
/// which Director stores as the text of a property list per attached
/// behavior (`[#mylocz: 5]`).
///
/// Covers what `put` writes and authors type: integers and floats (with a
/// sign), double-quoted strings, `#symbols`, `TRUE`/`FALSE`/`VOID`/`EMPTY`,
/// linear lists, property lists (symbol or string keys, `[:]` when empty),
/// and nesting of all of those. Anything else — an expression with
/// operators, a bare identifier, trailing junk — is not a literal, and the
/// parse answers `nil` so the caller can hand back VOID as Lingo does.
struct LingoLiteralParser {
    private let bytes: [UInt8]
    private var index = 0

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// The literal `text` spells, or `nil` when it isn't one.
    static func parse(_ text: String) -> LingoValue? {
        var parser = LingoLiteralParser(text)
        parser.skipSpaces()
        guard let value = parser.parseValue() else { return nil }
        parser.skipSpaces()
        return parser.index == parser.bytes.count ? value : nil
    }

    private mutating func parseValue() -> LingoValue? {
        guard let byte = peek() else { return nil }
        switch byte {
        case UInt8(ascii: "["): return parseList()
        case UInt8(ascii: "\""): return parseString()
        case UInt8(ascii: "#"): return parseSymbol()
        case UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: "0")...UInt8(ascii: "9"),
            UInt8(ascii: "."):
            return parseNumber()
        default:
            return parseKeyword()
        }
    }

    private mutating func parseList() -> LingoValue? {
        index += 1  // [
        skipSpaces()
        // `[:]` — an empty property list.
        if peek() == UInt8(ascii: ":") {
            index += 1
            skipSpaces()
            guard peek() == UInt8(ascii: "]") else { return nil }
            index += 1
            return .propertyList([])
        }
        if peek() == UInt8(ascii: "]") {
            index += 1
            return .list([])
        }
        var elements: [LingoValue] = []
        var pairs: [(key: LingoValue, value: LingoValue)] = []
        var isPropertyList: Bool?
        while true {
            skipSpaces()
            guard let first = parseValue() else { return nil }
            skipSpaces()
            if peek() == UInt8(ascii: ":") {
                // A key. Property lists are all pairs or nothing.
                if isPropertyList == false { return nil }
                isPropertyList = true
                index += 1
                skipSpaces()
                guard let value = parseValue() else { return nil }
                pairs.append((key: first, value: value))
            } else {
                if isPropertyList == true { return nil }
                isPropertyList = false
                elements.append(first)
            }
            skipSpaces()
            guard let separator = peek() else { return nil }
            index += 1
            if separator == UInt8(ascii: "]") { break }
            guard separator == UInt8(ascii: ",") else { return nil }
        }
        return isPropertyList == true ? .propertyList(pairs) : .list(elements)
    }

    private mutating func parseString() -> LingoValue? {
        index += 1  // opening quote
        var content: [UInt8] = []
        while let byte = peek() {
            index += 1
            if byte == UInt8(ascii: "\"") {
                // Lingo has no escapes; a doubled quote is how `put` writes
                // an embedded one.
                if peek() == UInt8(ascii: "\"") {
                    index += 1
                    content.append(byte)
                    continue
                }
                return .string(String(decoding: content, as: UTF8.self))
            }
            content.append(byte)
        }
        return nil  // unterminated
    }

    private mutating func parseSymbol() -> LingoValue? {
        index += 1  // #
        let name = readIdentifier()
        return name.isEmpty ? nil : .symbol(name)
    }

    private mutating func parseNumber() -> LingoValue? {
        let start = index
        if let sign = peek(), sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") {
            index += 1
        }
        var sawDigit = false
        var sawDot = false
        while let byte = peek() {
            if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
                sawDigit = true
            } else if byte == UInt8(ascii: "."), !sawDot {
                sawDot = true
            } else if (byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E")), sawDigit {
                // Exponent: optional sign, then digits.
                index += 1
                if let sign = peek(), sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") {
                    index += 1
                }
                sawDot = true
                continue
            } else {
                break
            }
            index += 1
        }
        guard sawDigit else { return nil }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if !sawDot, let integer = Int(text) { return .integer(integer) }
        if let double = Double(text) { return .float(double) }
        return nil
    }

    private mutating func parseKeyword() -> LingoValue? {
        let word = readIdentifier()
        switch word.asciiLowercased() {
        case "true": return .integer(1)
        case "false": return .integer(0)
        case "void": return .void
        case "empty": return .string("")
        default: return nil
        }
    }

    private mutating func readIdentifier() -> String {
        let start = index
        while let byte = peek(),
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
                || byte == UInt8(ascii: "_")
        {
            index += 1
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private func peek() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private mutating func skipSpaces() {
        while let byte = peek(),
            byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r")
                || byte == UInt8(ascii: "\n")
        {
            index += 1
        }
    }
}
