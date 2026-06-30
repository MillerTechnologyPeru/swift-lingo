// LingoValue.swift
// LingoRuntime module - Embedded Swift compatible

public final class LingoListClass: @unchecked Sendable {
    public var elements: [LingoValue]
    public init(_ elements: [LingoValue]) { self.elements = elements }
}

public final class LingoPropertyListClass: @unchecked Sendable {
    public var elements: [(key: LingoValue, value: LingoValue)]
    public init(_ elements: [(key: LingoValue, value: LingoValue)]) { self.elements = elements }
}

/// Represents a value in the Lingo runtime.
@dynamicMemberLookup
@dynamicCallable
public enum LingoValue {
    case void
    case integer(Int)
    case float(Double)
    case string(String)
    case symbol(String)
    case listType(LingoListClass)
    case propertyListType(LingoPropertyListClass)
    case object(LingoObject)
    case boundMethod(LingoObject, String)
    case globalFunction(String)

    public static func list(_ elements: [LingoValue]) -> LingoValue {
        return .listType(LingoListClass(elements))
    }

    public static func propertyList(_ elements: [(key: LingoValue, value: LingoValue)]) -> LingoValue {
        return .propertyListType(LingoPropertyListClass(elements))
    }

    /// Accesses properties on Lingo objects dynamically.
    public subscript(dynamicMember member: String) -> LingoValue {
        get {
            if member.caseInsensitiveEquals("count") {
                switch self {
                case .listType(let arr): return .integer(arr.elements.count)
                case .propertyListType(let props): return .integer(props.elements.count)
                case .string(let s): return .integer(s.count)
                default: return .integer(0)
                }
            }

            if case .object(let obj) = self {
                let prop = obj.getProperty(member)
                if case .void = prop {} else { return prop }
                return .boundMethod(obj, member)
            }
            // For now, property lookups on lists/strings are ignored or return void
            return .void
        }
        nonmutating set {
            if case .object(let obj) = self {
                obj.setProperty(member, value: newValue)
            }
        }
    }

    /// Sets a property on the underlying Lingo object.
    public func setProperty(_ name: String, value: LingoValue) {
        if case .object(let obj) = self {
            obj.setProperty(name, value: value)
        }
    }

    /// 1-based indexing for Lingo lists and property lists.
    public subscript(index: LingoValue) -> LingoValue {
        get {
            switch self {
            case .listType(let arr):
                if case .integer(let idx) = index {
                    if idx >= 1 && idx <= arr.elements.count {
                        return arr.elements[idx - 1]
                    }
                }
            case .propertyListType(let props):
                if case .integer(let idx) = index {
                    if idx >= 1 && idx <= props.elements.count {
                        return props.elements[idx - 1].value
                    }
                } else {
                    for prop in props.elements {
                        if LingoValue.equalsBool(lhs: prop.key, rhs: index) {
                            return prop.value
                        }
                    }
                }
            case .string(let s):
                if case .integer(let idx) = index {
                    if idx >= 1 && idx <= s.count {
                        let strIdx = s.index(s.startIndex, offsetBy: idx - 1)
                        return .string(String(s[strIdx]))
                    }
                }
            default:
                break
            }
            return .void
        }
        nonmutating set {
            // Managed by setElement
        }
    }

    /// Mutates an element at a given 1-based index or key.
    public func setElement(index: LingoValue, value: LingoValue) {
        switch self {
        case .listType(let arr):
            if case .integer(let idx) = index {
                if idx >= 1 && idx <= arr.elements.count {
                    arr.elements[idx - 1] = value
                }
            }
        case .propertyListType(let props):
            if case .integer(let idx) = index {
                if idx >= 1 && idx <= props.elements.count {
                    props.elements[idx - 1].value = value
                }
            } else {
                for i in 0..<props.elements.count {
                    if LingoValue.equalsBool(lhs: props.elements[i].key, rhs: index) {
                        props.elements[i].value = value
                        return
                    }
                }
                props.elements.append((key: index, value: value))
            }
        default:
            break
        }
    }

    /// 1-based string chunking (e.g. `char 1 to 5`).
    public func getRange(start: LingoValue, end: LingoValue) -> LingoValue {
        guard case .string(let s) = self,
            case .integer(let sIdx) = start,
            case .integer(let eIdx) = end
        else { return .void }

        let safeStart = Swift.max(1, sIdx)
        let safeEnd = Swift.min(s.count, eIdx)
        if safeStart > safeEnd || safeStart > s.count { return .string("") }

        let startStrIdx = s.index(s.startIndex, offsetBy: safeStart - 1)
        let endStrIdx = s.index(s.startIndex, offsetBy: safeEnd)
        return .string(String(s[startStrIdx..<endStrIdx]))
    }

    /// 0-based range extraction for Swift convenience.
    public func getRange(start: Int, end: Int) -> LingoValue {
        guard case .string(let s) = self else { return .void }
        let safeStart = Swift.max(0, start)
        let safeEnd = Swift.min(s.count, end)
        if safeStart > safeEnd || safeStart >= s.count { return .string("") }

        let startStrIdx = s.index(s.startIndex, offsetBy: safeStart)
        let endStrIdx = s.index(s.startIndex, offsetBy: safeEnd)
        return .string(String(s[startStrIdx..<endStrIdx]))
    }

    /// Calls a bound method or global function dynamically.
    public func dynamicallyCall(withArguments args: [LingoValue]) -> LingoValue {
        switch self {
        case .boundMethod(let obj, let name):
            return obj.callMethod(name, args: args)
        case .globalFunction(let name):
            return LingoEnvironment.shared.callGlobal(name, args: args)
        default:
            return .void
        }
    }

    /// Evaluates the value as a boolean for conditionals.
    public func asBool() -> Bool {
        switch self {
        case .integer(let v): return v != 0
        case .float(let v): return v != 0
        case .string(let v): return v.caseInsensitiveEquals("true")
        case .void: return false
        default: return true
        }
    }

    // MARK: - Relational Operators (Bool returning)

    /// Performs a deep equality comparison and returns a Bool.
    public static func equalsBool(lhs: LingoValue, rhs: LingoValue) -> Bool {
        switch (lhs, rhs) {
        case (.void, .void): return true
        case (.integer(let l), .integer(let r)): return l == r
        case (.float(let l), .float(let r)): return l == r
        case (.integer(let l), .float(let r)): return Double(l) == r
        case (.float(let l), .integer(let r)): return l == Double(r)
        case (.string(let l), .string(let r)): return l.caseInsensitiveEquals(r)
        case (.symbol(let l), .symbol(let r)): return l.caseInsensitiveEquals(r)
        case (.symbol(let l), .string(let r)): return l.caseInsensitiveEquals(r)
        case (.string(let l), .symbol(let r)): return l.caseInsensitiveEquals(r)
        case (.object(let l), .object(let r)): return l === r
        case (.listType(let l), .listType(let r)):
            if l.elements.count != r.elements.count { return false }
            for i in 0..<l.elements.count { if !equalsBool(lhs: l.elements[i], rhs: r.elements[i]) { return false } }
            return true
        case (.propertyListType(let l), .propertyListType(let r)):
            if l.elements.count != r.elements.count { return false }
            for i in 0..<l.elements.count {
                if !equalsBool(lhs: l.elements[i].key, rhs: r.elements[i].key) { return false }
                if !equalsBool(lhs: l.elements[i].value, rhs: r.elements[i].value) { return false }
            }
            return true
        default: return false
        }
    }

    /// Performs a less-than comparison and returns a Bool.
    public static func lessThanBool(lhs: LingoValue, rhs: LingoValue) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return l < r
        case (.float(let l), .float(let r)): return l < r
        case (.integer(let l), .float(let r)): return Double(l) < r
        case (.float(let l), .integer(let r)): return l < Double(r)
        case (.string(let l), .string(let r)): return l.caseInsensitiveLessThan(r)
        default: return false  // fallback
        }
    }

    // MARK: - Relational Operators (LingoValue returning)

    public static func == (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return equalsBool(lhs: lhs, rhs: rhs) ? .integer(1) : .integer(0)
    }

    public static func != (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return equalsBool(lhs: lhs, rhs: rhs) ? .integer(0) : .integer(1)
    }

    public static func < (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return lessThanBool(lhs: lhs, rhs: rhs) ? .integer(1) : .integer(0)
    }

    public static func > (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return (!lessThanBool(lhs: lhs, rhs: rhs) && !equalsBool(lhs: lhs, rhs: rhs)) ? .integer(1) : .integer(0)
    }

    public static func <= (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return (lessThanBool(lhs: lhs, rhs: rhs) || equalsBool(lhs: lhs, rhs: rhs)) ? .integer(1) : .integer(0)
    }

    public static func >= (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return !lessThanBool(lhs: lhs, rhs: rhs) ? .integer(1) : .integer(0)
    }

    // MARK: - Arithmetic Operators

    public static func + (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return .integer(l + r)
        case (.float(let l), .float(let r)): return .float(l + r)
        case (.listType(let l), .listType(let r)): return .listType(LingoListClass(l.elements + r.elements))
        case (.integer(let l), .float(let r)): return .float(Double(l) + r)
        case (.float(let l), .integer(let r)): return .float(l + Double(r))
        case (.string(let l), .string(let r)): return .string(l + r)
        default: return .void
        }
    }

    public static func - (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return .integer(l - r)
        case (.float(let l), .float(let r)): return .float(l - r)
        case (.integer(let l), .float(let r)): return .float(Double(l) - r)
        case (.float(let l), .integer(let r)): return .float(l - Double(r))
        default: return .void
        }
    }

    public static func * (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return .integer(l * r)
        case (.float(let l), .float(let r)): return .float(l * r)
        case (.integer(let l), .float(let r)): return .float(Double(l) * r)
        case (.float(let l), .integer(let r)): return .float(l * Double(r))
        default: return .void
        }
    }

    public static func / (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return r == 0 ? .void : .integer(l / r)
        case (.float(let l), .float(let r)): return .float(l / r)
        case (.integer(let l), .float(let r)): return .float(Double(l) / r)
        case (.float(let l), .integer(let r)): return .float(l / Double(r))
        default: return .void
        }
    }

    public static func % (lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        guard case .integer(let l) = lhs, case .integer(let r) = rhs, r != 0 else { return .void }
        return .integer(l % r)
    }

    public static prefix func - (value: LingoValue) -> LingoValue {
        switch value {
        case .integer(let v): return .integer(-v)
        case .float(let v): return .float(-v)
        default: return .void
        }
    }

    // MARK: - Utilities

    public func chunk(_ type: String, start: LingoValue, end: LingoValue?) -> LingoValue {
        guard case .string(let string) = self, let startIndex = start.asInteger() else { return .void }
        let endIndex = end?.asInteger() ?? startIndex
        let chunks = splitIntoChunks(string, type: type)
        let lowerBound = Swift.max(1, startIndex)
        let upperBound = Swift.min(chunks.count, endIndex)
        if lowerBound > upperBound || lowerBound > chunks.count { return .string("") }
        return .string(chunks[(lowerBound - 1)..<upperBound].joined(separator: chunkJoiner(for: type)))
    }

    public func lastChunk(_ type: String) -> LingoValue {
        guard case .string(let string) = self else { return .void }
        return .string(splitIntoChunks(string, type: type).last ?? "")
    }

    public func chunkCount(_ type: String) -> LingoValue {
        guard case .string(let string) = self else { return .integer(0) }
        return .integer(splitIntoChunks(string, type: type).count)
    }

    public func asInteger() -> Int? {
        switch self {
        case .integer(let v): return v
        case .float(let v): return Int(v)
        case .string(let v): return Int(v)
        default: return nil
        }
    }

    /// String form used by the concatenation operators (`&` and `&&`),
    /// which coerce numbers to strings before joining.
    public func asString() -> String {
        switch self {
        case .string(let v): return v
        case .symbol(let v): return v
        case .integer(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .void: return ""
        default: return ""
        }
    }

    /// Lingo `&` operator: concatenates the string forms of both values.
    public func concat(_ other: LingoValue) -> LingoValue {
        return .string(self.asString() + other.asString())
    }

    /// Lingo `&&` operator: concatenates the string forms with a single space between them.
    public func concatSpace(_ other: LingoValue) -> LingoValue {
        return .string(self.asString() + " " + other.asString())
    }

    private func splitIntoChunks(_ string: String, type: String) -> [String] {
        switch type.asciiLowercased() {
        case "char": return string.map { String($0) }
        case "word": return string.split { $0 == " " || $0 == "\n" || $0 == "\t" }.map(String.init)
        case "item": return string.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        case "line", "paragraph": return string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        default: return [string]
        }
    }

    private func chunkJoiner(for type: String) -> String {
        switch type.asciiLowercased() {
        case "word": return " "
        case "item": return ","
        case "line", "paragraph": return "\n"
        default: return ""
        }
    }

    /// Checks if a string or list contains the given value.
    public func contains(_ other: LingoValue) -> LingoValue {
        switch (self, other) {
        case (.string(let s), .string(let substr)):
            return s.caseInsensitiveContains(substr) ? .integer(1) : .integer(0)
        case (.listType(let l), _):
            for item in l.elements {
                if LingoValue.equalsBool(lhs: item, rhs: other) {
                    return .integer(1)
                }
            }
            return .integer(0)
        default:
            return .integer(0)
        }
    }

    /// Checks if a string starts with the given prefix.
    public func starts(with other: LingoValue) -> LingoValue {
        if case .string(let s) = self, case .string(let prefix) = other {
            return s.caseInsensitiveStartsWith(prefix) ? .integer(1) : .integer(0)
        }
        return .integer(0)
    }
}

public func ~= (pattern: LingoValue, value: LingoValue) -> Bool {
    return LingoValue.equalsBool(lhs: pattern, rhs: value)
}

// MARK: - Swift Subscript

extension LingoValue {
    /// Explicit count property to shadow Sequence.count(where:)
    public var count: LingoValue {
        switch self {
        case .listType(let arr): return .integer(arr.elements.count)
        case .propertyListType(let props): return .integer(props.elements.count)
        case .string(let s): return .integer(s.count)
        default: return .integer(0)
        }
    }

    /// 0-based conventional Swift subscript. Not used by transpiler.
    public subscript(position: Int) -> LingoValue {
        get {
            switch self {
            case .listType(let arr): return arr.elements[position]
            case .propertyListType(let props): return props.elements[position].value
            default: return .void
            }
        }
        set {
            switch self {
            case .listType(let arr):
                arr.elements.append(newValue)
            case .propertyListType(let props):
                // Append without key for now if used via random append
                props.elements.append((key: .void, value: newValue))
            default:
                break
            }
        }
    }
}

// MARK: - Swift Iteration Support

extension LingoValue {
    public func asSequence() -> [LingoValue] {
        switch self {
        case .listType(let arr): return arr.elements
        case .propertyListType(let props): return props.elements.map { $0.value }
        default: return []
        }
    }
}
