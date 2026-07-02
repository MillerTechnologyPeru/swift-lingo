import Testing
import BinaryParsing
import LingoAST
import LingoParser

@testable import LingoBytecode

/// Assembles a minimal handler + script chunk from hand-encoded bytecode and
/// decompiles it, so each fixture below only needs to state its bytes and
/// name table. Mirrors `DecompilerFixtureTests.swift`'s helper of the same
/// shape; kept as its own file-local copy since Swift test files don't share
/// `private` helpers across files in the same target.
private func decompiledStatements(
    bytes: [UInt8],
    names: [String],
    handlers: [HandlerDef] = [],
    literals: [LiteralValue] = [],
    version: UInt16 = 500
) throws -> [Statement] {
    let bytecodeArray = try bytes.withParserSpan { span -> [Bytecode] in
        var array: [Bytecode] = []
        while !span.isEmpty {
            array.append(try Bytecode(parsing: &span))
        }
        return array
    }
    let handler = HandlerDef(
        nameId: 0, bytecodeArray: bytecodeArray, argumentNameIds: [], localNameIds: [], globalNameIds: [])
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: handlers + [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    return LingoBytecode.decompile(handler: handler, chunk: chunk, names: names, version: version)
}

/// Renders `body` (wrapped in an `on handlerName ... end` handler, the shape
/// `LingoBytecode.decompile` itself never produces since it hands back a bare
/// body) to source text, then re-parses that text and returns the result, so
/// callers can assert the round trip reproduces the original statements.
///
/// Mirrors `RoundTripValidationTests.allJunkbotFilesRoundTrip()` in
/// `LingoParserTests` (parse -> render -> re-parse -> compare), but seeded
/// from bytecode-decompiled statements instead of real `.ls` source text.
private func renderAndReparse(
    handlerName: String,
    arguments: [String] = [],
    body: [Statement]
) async -> (source: String, reparsed: Script, skippedNonNewlineTokens: Int) {
    let original = Statement.handler(name: handlerName, arguments: arguments, body: body)
    let source = await Script(statements: [original]).toLingoSource()

    var lexer = Lexer(input: source)
    let tokens = lexer.tokenize()
    let parser = Parser(tokens: tokens)
    let reparsed = parser.parseScript()
    let skippedNonNewline = parser.skippedTokens.filter { $0 != .newline }.count

    return (source, reparsed, skippedNonNewline)
}

@Test func renderedArithmeticAssignmentReparsesIdentically() async throws {
    // global a, b, x
    // x = a + b
    let bytes: [UInt8] = [
        0x49, 0x00,  // GetGlobal a
        0x49, 0x01,  // GetGlobal b
        0x05,  // Add
        0x4f, 0x02,  // SetGlobal x
        0x01  // Ret
    ]
    let body = try decompiledStatements(bytes: bytes, names: ["a", "b", "x"])
    let (source, reparsed, skipped) = await renderAndReparse(handlerName: "doMath", body: body)

    #expect(skipped == 0, "Unexpected skipped tokens rendering:\n\(source)")
    #expect(reparsed.statements == [.handler(name: "doMath", arguments: [], body: body)])
}

@Test func renderedPropertyGetReparsesIdentically() async throws {
    // global obj, x
    // x = obj.prop
    let bytes: [UInt8] = [
        0x49, 0x00,  // GetGlobal obj
        0x61, 0x01,  // GetObjProp prop
        0x4f, 0x02,  // SetGlobal x
        0x01  // Ret
    ]
    let body = try decompiledStatements(bytes: bytes, names: ["obj", "prop", "x"])
    let (source, reparsed, skipped) = await renderAndReparse(handlerName: "readProp", body: body)

    #expect(skipped == 0, "Unexpected skipped tokens rendering:\n\(source)")
    #expect(reparsed.statements == [.handler(name: "readProp", arguments: [], body: body)])
}

@Test func renderedPropertySetReparsesIdentically() async throws {
    // global obj
    // obj.prop = 5
    let bytes: [UInt8] = [
        0x49, 0x00,  // GetGlobal obj
        0x41, 0x05,  // PushInt8 5
        0x62, 0x01,  // SetObjProp prop
        0x01  // Ret
    ]
    let body = try decompiledStatements(bytes: bytes, names: ["obj", "prop"])
    let (source, reparsed, skipped) = await renderAndReparse(handlerName: "writeProp", body: body)

    #expect(skipped == 0, "Unexpected skipped tokens rendering:\n\(source)")
    #expect(reparsed.statements == [.handler(name: "writeProp", arguments: [], body: body)])
}

@Test func renderedLocalHandlerCallReparsesToEquivalentFunctionCall() async throws {
    // global x
    // x = add(1, 2)
    //
    // `LingoBytecode.decompile` represents both `LocalCall` and `ExtCall` as
    // `Expression.call(name:args: .argList(...))`, which always renders with
    // parentheses (`"add(1, 2)"`). `LingoParser` treats a parenthesized
    // call as `Expression.functionCall`, not `.call` (the latter is reserved
    // for paren-less command syntax like `put 1 into x`), so this is a
    // pre-existing, deterministic divergence between the two `Expression`
    // producers for every decompiled call — not a rendering defect. This
    // test documents the actual round-tripped shape rather than asserting a
    // byte-for-byte match that the current AST can't achieve.
    let addHandler = HandlerDef(
        nameId: 1, bytecodeArray: [], argumentNameIds: [], localNameIds: [], globalNameIds: [])
    let bytes: [UInt8] = [
        0x41, 0x01,  // PushInt8 1
        0x41, 0x02,  // PushInt8 2
        0x43, 0x02,  // PushArgList 2
        0x56, 0x00,  // LocalCall 0 (addHandler)
        0x4f, 0x00,  // SetGlobal x
        0x01  // Ret
    ]
    let body = try decompiledStatements(bytes: bytes, names: ["x", "add"], handlers: [addHandler])
    let (source, reparsed, skipped) = await renderAndReparse(handlerName: "useAdd", body: body)

    #expect(skipped == 0, "Unexpected skipped tokens rendering:\n\(source)")
    #expect(
        reparsed.statements == [
            .handler(
                name: "useAdd", arguments: [],
                body: [
                    .assignment(
                        target: .identifier("x"),
                        value: .functionCall(
                            target: nil, name: "add", arguments: [.integer(1), .integer(2)]),
                        syntax: .dot)
                ])
        ])
}

@Test func renderedRepeatWhileLoopReparsesIdentically() async throws {
    // repeat while x
    // end repeat
    let bytes: [UInt8] = [
        0x49, 0x00,  // 0: GetGlobal x
        0x55, 0x04,  // 2: JmpIfZ -> pos 6 (end of loop)
        0x54, 0x04,  // 4: EndRepeat -> pos 0 (recheck condition)
        0x01  // 6: Ret
    ]
    let body = try decompiledStatements(bytes: bytes, names: ["x"])
    let (source, reparsed, skipped) = await renderAndReparse(handlerName: "loopWhileX", body: body)

    #expect(skipped == 0, "Unexpected skipped tokens rendering:\n\(source)")
    #expect(reparsed.statements == [.handler(name: "loopWhileX", arguments: [], body: body)])
}
