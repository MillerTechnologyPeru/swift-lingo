// LingoObject.swift
// LingoRuntime module - Embedded Swift compatible

/// Base class for Lingo objects, representing instances of Lingo classes.
@dynamicMemberLookup
@dynamicCallable
open class LingoObject {
    // Named to avoid colliding with Lingo's own built-in `the environment`
    // system property: if this were a plain `environment` stored property,
    // `self.\`environment\`` in generated code (or any dynamic-member access
    // Lingo scripts write as "the environment") would resolve directly to
    // this property instead of falling through `@dynamicMemberLookup` to
    // `getProperty`/global lookup, silently breaking `the environment`.
    public let lingoEnvironment: LingoEnvironment

    public init(environment: LingoEnvironment) {
        self.lingoEnvironment = environment
    }

    open func getProperty(_ name: String) -> LingoValue { return .void }
    open func setProperty(_ name: String, value: LingoValue) {}
    open func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
        return lingoEnvironment.callGlobal(name, args: args)
    }

    public subscript(dynamicMember member: String) -> LingoValue {
        get {
            let prop = getProperty(member)
            if case .void = prop {} else { return prop }

            let glob = lingoEnvironment.getGlobal(member)
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
