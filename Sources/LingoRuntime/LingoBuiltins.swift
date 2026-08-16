// LingoBuiltins.swift
// LingoRuntime module - Embedded Swift compatible

/// Lingo's language-level functions as plain Swift functions, named after
/// their Lingo spellings (`voidP`, `numToChar`, ...).
///
/// Each is callable directly — from host code, tests, or other builtins —
/// and `LingoEnvironment.registerStandardBuiltins` wires the same functions
/// up by name for compiled Lingo, which calls them as named globals.
public enum LingoBuiltins {

    // MARK: - count

    public static func count(_ value: LingoValue) -> LingoValue {
        value.count
    }

    // MARK: - Type inspection

    public static func voidP(_ value: LingoValue) -> LingoValue {
        if case .void = value { return .integer(1) }
        return .integer(0)
    }

    /// `ilk(x)` names the type; `ilk(x, #type)` asks whether x is that type.
    public static func ilk(_ value: LingoValue, _ type: LingoValue? = nil) -> LingoValue {
        let kind = ilkName(of: value)
        if let type, case .symbol(let wanted) = type {
            var matches = kind.caseInsensitiveEquals(wanted)
            // A property list is also a list, as Lingo reports it.
            if !matches, wanted.caseInsensitiveEquals("list") {
                matches = value.isList
            }
            return .integer(matches ? 1 : 0)
        }
        return .symbol(kind)
    }

    public static func listP(_ value: LingoValue) -> LingoValue {
        .integer(value.isList ? 1 : 0)
    }

    public static func stringP(_ value: LingoValue) -> LingoValue {
        if case .string = value { return .integer(1) }
        return .integer(0)
    }

    public static func symbolP(_ value: LingoValue) -> LingoValue {
        if case .symbol = value { return .integer(1) }
        return .integer(0)
    }

    public static func objectP(_ value: LingoValue) -> LingoValue {
        if case .object = value { return .integer(1) }
        return .integer(0)
    }

    public static func integerP(_ value: LingoValue) -> LingoValue {
        if case .integer = value { return .integer(1) }
        return .integer(0)
    }

    public static func floatP(_ value: LingoValue) -> LingoValue {
        if case .float = value { return .integer(1) }
        return .integer(0)
    }

    // MARK: - Coercions

    public static func string(_ value: LingoValue) -> LingoValue {
        .string(value.asString())
    }

    public static func symbol(_ value: LingoValue) -> LingoValue {
        .symbol(value.asString())
    }

    public static func integer(_ value: LingoValue) -> LingoValue {
        guard let integer = value.asInteger() else { return .void }
        return .integer(integer)
    }

    public static func float(_ value: LingoValue) -> LingoValue {
        switch value {
        case .float(let double): return .float(double)
        case .integer(let integer): return .float(Double(integer))
        default:
            guard let integer = value.asInteger() else { return .void }
            return .float(Double(integer))
        }
    }

    /// `value("42")` — parses a number out of a string; non-strings pass
    /// through unchanged, unparseable text is VOID.
    public static func value(_ input: LingoValue) -> LingoValue {
        guard case .string(let text) = input else { return input }
        let trimmed = String(
            text.drop(while: { $0 == " " || $0 == "\t" })
                .reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
        if let integer = Int(trimmed) { return .integer(integer) }
        if let double = Double(trimmed) { return .float(double) }
        return .void
    }

    // MARK: - Strings

    public static func length(_ value: LingoValue) -> LingoValue {
        guard case .string(let text) = value else { return .integer(0) }
        return .integer(text.count)
    }

    /// `offset(needle, haystack)` — 1-based, 0 when absent, case-insensitive
    /// like the rest of Lingo's string handling. This guards `repeat while`
    /// loops all over real movies (`repeat while offset(numToChar(10), t) >
    /// 0`), so a VOID stand-in changes loop behavior rather than failing
    /// visibly.
    public static func offset(_ needle: LingoValue, _ haystack: LingoValue) -> LingoValue {
        let needleChars = Array(needle.asString().asciiLowercased())
        let haystackChars = Array(haystack.asString().asciiLowercased())
        guard !needleChars.isEmpty, !haystackChars.isEmpty,
            needleChars.count <= haystackChars.count
        else { return .integer(0) }
        for start in 0...(haystackChars.count - needleChars.count) {
            var matches = true
            for i in 0..<needleChars.count where haystackChars[start + i] != needleChars[i] {
                matches = false
                break
            }
            if matches { return .integer(start + 1) }
        }
        return .integer(0)
    }

    /// `chars(string, first, last)` — inclusive 1-based slice.
    public static func chars(
        _ text: LingoValue, _ first: LingoValue, _ last: LingoValue
    ) -> LingoValue {
        guard case .string(let string) = text, let first = first.asInteger(),
            let last = last.asInteger()
        else { return .string("") }
        let characters = Array(string)
        let lower = Swift.max(1, first)
        let upper = Swift.min(characters.count, last)
        guard lower <= upper else { return .string("") }
        return .string(String(characters[(lower - 1)..<upper]))
    }

    public static func numToChar(_ code: LingoValue) -> LingoValue {
        guard let integer = code.asInteger(),
            let scalar = Unicode.Scalar(UInt32(bitPattern: Int32(truncatingIfNeeded: integer)) & 0xFF)
        else { return .string("") }
        return .string(String(Character(scalar)))
    }

    public static func charToNum(_ text: LingoValue) -> LingoValue {
        guard case .string(let string) = text, let first = string.unicodeScalars.first else {
            return .integer(0)
        }
        return .integer(Int(first.value))
    }

    // MARK: - Arithmetic

    public static func abs(_ value: LingoValue) -> LingoValue {
        switch value {
        case .integer(let integer): return .integer(integer < 0 ? -integer : integer)
        case .float(let double): return .float(double < 0 ? -double : double)
        default: return .void
        }
    }

    /// `max`/`min` accept either a run of arguments or a single list.
    public static func max(_ values: [LingoValue]) -> LingoValue {
        extreme(of: values, keepingLeft: false)
    }

    public static func min(_ values: [LingoValue]) -> LingoValue {
        extreme(of: values, keepingLeft: true)
    }

    // MARK: - Helpers

    private static func ilkName(of value: LingoValue) -> String {
        switch value {
        case .void: return "void"
        case .integer: return "integer"
        case .float: return "float"
        case .string: return "string"
        case .symbol: return "symbol"
        case .listType: return "list"
        case .propertyListType: return "propList"
        case .object, .boundMethod, .globalFunction: return "object"
        }
    }

    private static func extreme(of args: [LingoValue], keepingLeft: Bool) -> LingoValue {
        var values = args
        if args.count == 1, case .listType(let list) = args[0] {
            values = list.elements
        }
        guard var best = values.first else { return .void }
        for value in values.dropFirst() {
            let takeNew =
                keepingLeft
                ? LingoValue.lessThanBool(lhs: value, rhs: best)
                : LingoValue.lessThanBool(lhs: best, rhs: value)
            if takeNew { best = value }
        }
        return best
    }
}
