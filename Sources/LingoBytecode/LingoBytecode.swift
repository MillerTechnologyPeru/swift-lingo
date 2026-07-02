import LingoAST

/// Parses Director's compiled Lingo bytecode format (opcode streams, literal
/// pools, name tables) and decompiles it into the same `LingoAST.Statement`/
/// `Expression` types `LingoParser` produces from source text — one AST
/// shape, two producers.
///
/// Resolving name ids into strings requires the movie's flat name table (the
/// `Lnam` chunk), which is a generic Director resource chunk rather than
/// anything Lingo-specific, so parsing it is outside this module's scope —
/// callers supply the resolved `names` array.
public struct LingoBytecode {
    /// Decompiles one handler's opcode stream.
    ///
    /// - Parameters:
    ///   - handler: The handler's parsed bytecode and local/argument/global name-id tables.
    ///   - chunk: The script chunk `handler` belongs to — supplies the literal pool (`PushCons`) and the handler table (`LocalCall`).
    ///   - names: The movie's flat name table, shared across every script in it. Resolves the name ids `chunk`/`handler` reference into strings.
    ///   - version: The Director file format version (e.g. `500` for Director 5), which selects the variable-id scaling factor and several version-dependent bytecode shapes (Director 4's `Get`/`Set` opcodes, chunk-reference cast-library ids, the `.dot`-vs-`.verbose` `LingoSyntax` used for the result).
    ///   - capitalX: Whether this script's context chunk uses the newer `LctX` name-table indirection, which addresses variables directly rather than through the version-dependent scaling factor. Defaults to `false`.
    public static func decompile(
        handler: HandlerDef,
        chunk: ScriptChunk,
        names: [String],
        version: UInt16,
        capitalX: Bool = false
    ) -> [Statement] {
        let multiplier: UInt32 = capitalX ? 1 : (version >= 500 ? 8 : 6)
        let state = DecompilerState(
            handler: handler, chunk: chunk, names: names, version: version, multiplier: multiplier)
        state.parse()
        let syntax: LingoSyntax = version >= 500 ? .dot : .verbose
        return state.rootBlock.asStatements(syntax: syntax)
    }
}
