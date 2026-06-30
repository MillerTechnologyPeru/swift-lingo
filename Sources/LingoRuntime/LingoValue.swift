// LingoValue.swift
// LingoRuntime module - Embedded Swift compatible

public enum LingoValue: Equatable {
    case void
    case integer(Int)
    case float(Double) // Lingo floats are typically double precision
    case string(String)
    case symbol(String)
    case list([LingoValue])
    case propertyList([(key: LingoValue, value: LingoValue)])
    case object(LingoObject)
}

open class LingoObject {
    public init() {}
    open func getProperty(_ name: String) -> LingoValue { return .void }
    open func setProperty(_ name: String, value: LingoValue) {}
}

extension LingoValue {
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
}
