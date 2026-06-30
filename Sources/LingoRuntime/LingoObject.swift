// LingoObject.swift
// LingoRuntime module - Embedded Swift compatible

/// Base class for Lingo objects, representing instances of Lingo classes.
@dynamicMemberLookup
@dynamicCallable
open class LingoObject {
    public init() {}

    open func getProperty(_ name: String) -> LingoValue { return .void }
    open func setProperty(_ name: String, value: LingoValue) {}
    open func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
        return LingoEnvironment.shared.callGlobal(name, args: args)
    }

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
