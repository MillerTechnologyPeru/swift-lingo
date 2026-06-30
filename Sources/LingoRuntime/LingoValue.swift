// LingoValue.swift
// LingoRuntime module - Embedded Swift compatible

/// Represents a value in the Lingo runtime.
@dynamicMemberLookup
@dynamicCallable
public enum LingoValue {
    case void
    case integer(Int)
    case float(Double)
    case string(String)
    case symbol(String)
    case list([LingoValue])
    case propertyList([(key: LingoValue, value: LingoValue)])
    case object(LingoObject)
    case boundMethod(LingoObject, String)
    case globalFunction(String)
    
    /// Accesses properties on Lingo objects dynamically.
    public subscript(dynamicMember member: String) -> LingoValue {
        get {
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
            case .list(let arr):
                if case .integer(let idx) = index {
                    if idx >= 1 && idx <= arr.count {
                        return arr[idx - 1]
                    }
                }
            case .propertyList(let props):
                if case .integer(let idx) = index {
                    if idx >= 1 && idx <= props.count {
                        return props[idx - 1].value
                    }
                } else {
                    for prop in props {
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
    public mutating func setElement(index: LingoValue, value: LingoValue) {
        switch self {
        case .list(var arr):
            if case .integer(let idx) = index {
                if idx >= 1 && idx <= arr.count {
                    arr[idx - 1] = value
                    self = .list(arr)
                }
            }
        case .propertyList(var props):
            if case .integer(let idx) = index {
                if idx >= 1 && idx <= props.count {
                    props[idx - 1].value = value
                    self = .propertyList(props)
                }
            } else {
                for i in 0..<props.count {
                    if LingoValue.equalsBool(lhs: props[i].key, rhs: index) {
                        props[i].value = value
                        self = .propertyList(props)
                        return
                    }
                }
                props.append((key: index, value: value))
                self = .propertyList(props)
            }
        default:
            break
        }
    }
    
    /// 1-based string chunking (e.g. `char 1 to 5`).
    public func getRange(start: LingoValue, end: LingoValue) -> LingoValue {
        guard case .string(let s) = self,
              case .integer(let sIdx) = start,
              case .integer(let eIdx) = end else { return .void }
        
        let safeStart = max(1, sIdx)
        let safeEnd = min(s.count, eIdx)
        if safeStart > safeEnd || safeStart > s.count { return .string("") }
        
        let startStrIdx = s.index(s.startIndex, offsetBy: safeStart - 1)
        let endStrIdx = s.index(s.startIndex, offsetBy: safeEnd)
        return .string(String(s[startStrIdx..<endStrIdx]))
    }
    
    /// 0-based range extraction for Swift convenience.
    public func getRange(start: Int, end: Int) -> LingoValue {
        guard case .string(let s) = self else { return .void }
        let safeStart = max(0, start)
        let safeEnd = min(s.count, end)
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
        case .string(let v): return v.lowercased() == "true"
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
        case (.string(let l), .string(let r)): return l.lowercased() == r.lowercased()
        case (.symbol(let l), .symbol(let r)): return l.lowercased() == r.lowercased()
        case (.symbol(let l), .string(let r)): return l.lowercased() == r.lowercased()
        case (.string(let l), .symbol(let r)): return l.lowercased() == r.lowercased()
        case (.object(let l), .object(let r)): return l === r
        case (.list(let l), .list(let r)):
            if l.count != r.count { return false }
            for i in 0..<l.count { if !equalsBool(lhs: l[i], rhs: r[i]) { return false } }
            return true
        case (.propertyList(let l), .propertyList(let r)):
            if l.count != r.count { return false }
            for i in 0..<l.count {
                if !equalsBool(lhs: l[i].key, rhs: r[i].key) { return false }
                if !equalsBool(lhs: l[i].value, rhs: r[i].value) { return false }
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
        case (.string(let l), .string(let r)): return l.lowercased() < r.lowercased()
        default: return false // fallback
        }
    }
    
    // MARK: - Relational Operators (LingoValue returning)
    
    public static func ==(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return equalsBool(lhs: lhs, rhs: rhs) ? .integer(1) : .integer(0)
    }
    
    public static func !=(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return equalsBool(lhs: lhs, rhs: rhs) ? .integer(0) : .integer(1)
    }
    
    public static func <(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return lessThanBool(lhs: lhs, rhs: rhs) ? .integer(1) : .integer(0)
    }
    
    public static func >(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return (!lessThanBool(lhs: lhs, rhs: rhs) && !equalsBool(lhs: lhs, rhs: rhs)) ? .integer(1) : .integer(0)
    }
    
    public static func <=(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return (lessThanBool(lhs: lhs, rhs: rhs) || equalsBool(lhs: lhs, rhs: rhs)) ? .integer(1) : .integer(0)
    }
    
    public static func >=(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        return !lessThanBool(lhs: lhs, rhs: rhs) ? .integer(1) : .integer(0)
    }
    
    // MARK: - Arithmetic Operators
    
    public static func +(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return .integer(l + r)
        case (.float(let l), .float(let r)): return .float(l + r)
        case (.integer(let l), .float(let r)): return .float(Double(l) + r)
        case (.float(let l), .integer(let r)): return .float(l + Double(r))
        case (.string(let l), .string(let r)): return .string(l + r)
        default: return .void
        }
    }
    
    public static func -(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return .integer(l - r)
        case (.float(let l), .float(let r)): return .float(l - r)
        case (.integer(let l), .float(let r)): return .float(Double(l) - r)
        case (.float(let l), .integer(let r)): return .float(l - Double(r))
        default: return .void
        }
    }
    
    public static func *(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return .integer(l * r)
        case (.float(let l), .float(let r)): return .float(l * r)
        case (.integer(let l), .float(let r)): return .float(Double(l) * r)
        case (.float(let l), .integer(let r)): return .float(l * Double(r))
        default: return .void
        }
    }
    
    public static func /(lhs: LingoValue, rhs: LingoValue) -> LingoValue {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return r == 0 ? .void : .integer(l / r)
        case (.float(let l), .float(let r)): return .float(l / r)
        case (.integer(let l), .float(let r)): return .float(Double(l) / r)
        case (.float(let l), .integer(let r)): return .float(l / Double(r))
        default: return .void
        }
    }
    
    // MARK: - Utilities
    
    /// Checks if a string or list contains the given value.
    public func contains(_ other: LingoValue) -> LingoValue {
        switch (self, other) {
        case (.string(let s), .string(let substr)):
            return s.lowercased().contains(substr.lowercased()) ? .integer(1) : .integer(0)
        case (.list(let arr), _):
            for item in arr {
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
            return s.lowercased().hasPrefix(prefix.lowercased()) ? .integer(1) : .integer(0)
        }
        return .integer(0)
    }
}

// MARK: - Swift Collection Conformance

extension LingoValue: RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = LingoValue
    
    public var startIndex: Int { 0 }
    
    public var endIndex: Int {
        switch self {
        case .list(let arr): return arr.count
        case .propertyList(let props): return props.count
        default: return 0
        }
    }
    
    /// 0-based conventional Swift subscript. Not used by transpiler.
    public subscript(position: Int) -> LingoValue {
        get {
            switch self {
            case .list(let arr): return arr[position]
            case .propertyList(let props): return props[position].value
            default: return .void
            }
        }
        set {
            switch self {
            case .list(var arr):
                arr[position] = newValue
                self = .list(arr)
            case .propertyList(var props):
                props[position].value = newValue
                self = .propertyList(props)
            default:
                break
            }
        }
    }
}

/// Base class for Lingo objects, representing instances of Lingo classes.
@dynamicMemberLookup
@dynamicCallable
open class LingoObject {
    public init() {}
    
    open func getProperty(_ name: String) -> LingoValue { return .void }
    open func setProperty(_ name: String, value: LingoValue) {}
    open func callMethod(_ name: String, args: [LingoValue]) -> LingoValue { return .void }
    
    public subscript(dynamicMember member: String) -> LingoValue {
        get {
            let prop = getProperty(member)
            if case .void = prop {} else { return prop }
            
            let glob = LingoEnvironment.shared.getGlobal(member)
            if case .void = glob {} else { return glob }
            
            return .boundMethod(self, member)
        }
        set {
            setProperty(member, value: newValue)
        }
    }
    
    public func dynamicallyCall(withArguments args: [LingoValue]) -> LingoValue {
        return .void
    }
}
