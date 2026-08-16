// LingoEnvironment.swift
// LingoRuntime module - Embedded Swift compatible

public class LingoEnvironment {
    /// Keyed by lowercased name — Lingo is case-insensitive, and these are
    /// the hottest lookups in the runtime: every global read, global write,
    /// and named function call goes through one. They were linear scans
    /// with a string compare per entry, which a movie registering hundreds
    /// of movie-script handlers turns into the dominant cost of running
    /// any script at all.
    private var globals: [String: LingoValue] = [:]
    private var globalFunctions: [String: ([LingoValue]) -> LingoValue] = [:]

    public init() {
        registerStandardBuiltins()
    }

    public func getGlobal(_ name: String) -> LingoValue {
        globals[name.asciiLowercased()] ?? .void
    }

    public func setGlobal(_ name: String, _ value: LingoValue) {
        globals[name.asciiLowercased()] = value
    }

    /// Registers a named function, replacing any existing one of that name
    /// — which is what lets a host override a standard builtin, and a
    /// movie's own handler shadow one.
    public func registerGlobalFunction(_ name: String, _ function: @escaping ([LingoValue]) -> LingoValue) {
        globalFunctions[name.asciiLowercased()] = function
    }

    public func callGlobal(_ name: String, args: [LingoValue]) -> LingoValue {
        guard let function = globalFunctions[name.asciiLowercased()] else { return .void }
        return function(args)
    }

    public func clear() {
        globals = [:]
        globalFunctions = [:]
    }
}
