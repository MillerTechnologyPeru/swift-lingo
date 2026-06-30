// LingoEnvironment.swift
// LingoRuntime module - Embedded Swift compatible

public class LingoEnvironment {
    nonisolated(unsafe) public static let shared = LingoEnvironment()
    
    private var globals: [(key: String, value: LingoValue)] = []
    private var globalFunctions: [(key: String, value: ([LingoValue]) -> LingoValue)] = []
    
    public init() {}
    
    public func getGlobal(_ name: String) -> LingoValue {
        let lower = name.lowercased()
        for i in 0..<globals.count {
            if globals[i].key == lower {
                return globals[i].value
            }
        }
        return .void
    }
    
    public func setGlobal(_ name: String, _ value: LingoValue) {
        let lower = name.lowercased()
        for i in 0..<globals.count {
            if globals[i].key == lower {
                globals[i] = (key: lower, value: value)
                return
            }
        }
        globals.append((key: lower, value: value))
    }
    
    public func registerGlobalFunction(_ name: String, _ function: @escaping ([LingoValue]) -> LingoValue) {
        let lower = name.lowercased()
        globalFunctions.append((key: lower, value: function))
    }
    
    public func callGlobal(_ name: String, args: [LingoValue]) -> LingoValue {
        let lower = name.lowercased()
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
