import LingoBytecode
import LingoRuntime

/// A stack-machine virtual machine that executes compiled Lingo bytecode
/// (`LingoBytecode.HandlerDef`) directly, using `LingoRuntime`'s value model
/// (`LingoValue`/`LingoObject`/`LingoEnvironment`) — the same runtime
/// `LingoTranspiler`'s ahead-of-time-compiled Swift output already uses.
///
/// `LingoVM` has no knowledge of any particular host runtime (no sprites,
/// cast members, movies, or stage). Anything host-specific is delegated
/// through `LingoVMHost`.
public enum LingoVM {
    /// Matches the reference implementation's call-stack depth limit, but as
    /// a catchable error (`LingoVMError.recursionLimitExceeded`) rather than
    /// a crash.
    public static let maxRecursionDepth = 50

    /// Executes `handler` to completion and returns its result (`.void` if
    /// the handler never explicitly leaves a value on the stack when it
    /// returns).
    ///
    /// - Parameters:
    ///   - handler: The compiled handler to run.
    ///   - chunk: The script chunk `handler` belongs to — supplies the literal pool (`PushCons`) and the handler table (`LocalCall`).
    ///   - names: The movie's flat name table, shared across every script in it.
    ///   - args: Argument values, matching positionally against `handler.argumentNameIds`.
    ///   - receiver: The object this handler is running against (`me`), if any.
    ///   - host: Resolves Director-specific concepts (the movie, sprites, cast members, ...) the VM has no knowledge of. `nil` degrades every Director-specific opcode to void/no-op.
    ///   - version: The Director file format version (e.g. `500` for Director 5) — selects the variable-id scaling factor and several version-dependent bytecode shapes, matching `LingoBytecode.decompile`.
    ///   - capitalX: Whether this script's context chunk uses the newer `LctX` name-table indirection. Defaults to `false`.
    public static func call(
        handler: HandlerDef,
        chunk: ScriptChunk,
        names: [String],
        args: [LingoValue] = [],
        receiver: LingoObject? = nil,
        host: LingoVMHost? = nil,
        version: UInt16,
        capitalX: Bool = false
    ) throws -> LingoValue {
        let multiplier: UInt32 = capitalX ? 1 : (version >= 500 ? 8 : 6)
        return try call(
            handler: handler, chunk: chunk, names: names, args: args, receiver: receiver, host: host,
            version: version, multiplier: multiplier, depth: 0)
    }

    static func call(
        handler: HandlerDef,
        chunk: ScriptChunk,
        names: [String],
        args: [LingoValue],
        receiver: LingoObject?,
        host: LingoVMHost?,
        version: UInt16,
        multiplier: UInt32,
        depth: Int
    ) throws -> LingoValue {
        let executor = LingoVMExecutor(
            handler: handler, chunk: chunk, names: names, args: args, receiver: receiver, host: host,
            version: version, multiplier: multiplier, depth: depth)
        return try executor.run()
    }
}
