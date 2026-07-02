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

    // Reentrancy guards for the ancestor-chain walks below, not
    // shared/global state — each is scoped to a single object instance and
    // only held for the duration of one outstanding delegation to that
    // object's own `ancestor`. A cyclic `ancestor` chain (however long)
    // necessarily revisits some object while its guard is still set; that's
    // exactly the signal used to stop recursing instead of looping forever.
    // (A plain iteration counter doesn't work here: each step calls the
    // ancestor's own public `getProperty`/`callMethod`, which — if that
    // ancestor doesn't recognize the name either — re-enters this same base
    // implementation on a fresh call stack with its own counter reset to
    // zero, so a counter alone never actually bounds a cycle.)
    private var isResolvingAncestorProperty = false
    private var isResolvingAncestorMethod = false

    public init(environment: LingoEnvironment) {
        self.lingoEnvironment = environment
    }

    /// Lingo's prototypal inheritance: an object with an `ancestor` property
    /// (itself just a regular declared property pointing at another object)
    /// inherits whatever properties it doesn't declare itself. A subclass
    /// that recognizes `name` as one of its own properties never reaches
    /// this base implementation at all; this only runs as the `super.
    /// getProperty(name)` fallback once a subclass's own lookup has already
    /// missed.
    open func getProperty(_ name: String) -> LingoValue {
        guard !name.caseInsensitiveEquals("ancestor"), !isResolvingAncestorProperty else { return .void }
        guard case .object(let ancestor) = getProperty("ancestor") else { return .void }
        isResolvingAncestorProperty = true
        defer { isResolvingAncestorProperty = false }
        return ancestor.getProperty(name)
    }

    open func setProperty(_ name: String, value: LingoValue) {}

    /// Mirrors `getProperty`'s ancestor-chain walk and cycle guard: a method
    /// declared anywhere in the chain wins over the final global-function
    /// fallback.
    open func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
        guard !isResolvingAncestorMethod, case .object(let ancestor) = getProperty("ancestor") else {
            return lingoEnvironment.callGlobal(name, args: args)
        }
        isResolvingAncestorMethod = true
        defer { isResolvingAncestorMethod = false }
        return ancestor.callMethod(name, args: args)
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
