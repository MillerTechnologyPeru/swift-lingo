// LingoEnvironment.swift
// LingoRuntime module - Embedded Swift compatible

public class LingoEnvironment {
    private var globals: [(key: String, value: LingoValue)] = []
    private var globalFunctions: [(key: String, value: ([LingoValue]) -> LingoValue)] = []

    public init() {
        registerStandardBuiltins()
    }

    public func getGlobal(_ name: String) -> LingoValue {
        let lower = name.asciiLowercased()
        for i in 0..<globals.count {
            if globals[i].key == lower {
                return globals[i].value
            }
        }
        return .void
    }

    public func setGlobal(_ name: String, _ value: LingoValue) {
        let lower = name.asciiLowercased()
        for i in 0..<globals.count {
            if globals[i].key == lower {
                globals[i] = (key: lower, value: value)
                return
            }
        }
        globals.append((key: lower, value: value))
    }

    /// Registers a named function, replacing any existing one of that name.
    ///
    /// Replacing rather than appending is what lets a host override a
    /// standard builtin, and a movie's own handler shadow one, since
    /// `callGlobal` answers with the first match it finds.
    public func registerGlobalFunction(_ name: String, _ function: @escaping ([LingoValue]) -> LingoValue) {
        let lower = name.asciiLowercased()
        for i in 0..<globalFunctions.count {
            if globalFunctions[i].key == lower {
                globalFunctions[i] = (key: lower, value: function)
                return
            }
        }
        globalFunctions.append((key: lower, value: function))
    }

    public func callGlobal(_ name: String, args: [LingoValue]) -> LingoValue {
        let lower = name.asciiLowercased()
        for i in 0..<globalFunctions.count {
            if globalFunctions[i].key == lower {
                return globalFunctions[i].value(args)
            }
        }
        return .void
    }

    public func clear() {
        globals = []
        globalFunctions = []
    }
}
