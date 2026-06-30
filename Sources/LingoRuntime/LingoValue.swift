// LingoValue.swift
// LingoRuntime module - Embedded Swift compatible

@dynamicMemberLookup
@dynamicCallable
public enum LingoValue: Equatable {
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
    
    public subscript(dynamicMember member: String) -> LingoValue {
        get {
            if case .object(let obj) = self {
                let prop = obj.getProperty(member)
                if prop != .void { return prop }
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
    
    public func asBool() -> Bool {
        switch self {
        case .integer(let v): return v != 0
        case .float(let v): return v != 0
        case .string(let v): return v.lowercased() == "true"
        case .void: return false
        default: return true
        }
    }
    
    public static func ==(lhs: LingoValue, rhs: LingoValue) -> Bool {
        switch (lhs, rhs) {
        case (.void, .void): return true
        case (.integer(let l), .integer(let r)): return l == r
        case (.float(let l), .float(let r)): return l == r
        case (.string(let l), .string(let r)): return l == r
        case (.symbol(let l), .symbol(let r)): return l == r
        case (.list(let l), .list(let r)): return l == r
        case (.propertyList(let l), .propertyList(let r)):
            if l.count != r.count { return false }
            for i in 0..<l.count {
                if l[i].key != r[i].key || l[i].value != r[i].value { return false }
            }
            return true
        case (.object(let l), .object(let r)):
            return l === r
        default:
            return false
        }
    }
    
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
    
    public static func <(lhs: LingoValue, rhs: LingoValue) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let l), .integer(let r)): return l < r
        case (.float(let l), .float(let r)): return l < r
        case (.integer(let l), .float(let r)): return Double(l) < r
        case (.float(let l), .integer(let r)): return l < Double(r)
        case (.string(let l), .string(let r)): return l < r
        default: return false
        }
    }
    
    public static func >(lhs: LingoValue, rhs: LingoValue) -> Bool {
        return rhs < lhs
    }
    
    public static func <=(lhs: LingoValue, rhs: LingoValue) -> Bool {
        return !(rhs < lhs)
    }
    
    public static func >=(lhs: LingoValue, rhs: LingoValue) -> Bool {
        return !(lhs < rhs)
    }
}

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
            if prop != .void { return prop }
            
            let glob = LingoEnvironment.shared.getGlobal(member)
            if glob != .void { return glob }
            
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
