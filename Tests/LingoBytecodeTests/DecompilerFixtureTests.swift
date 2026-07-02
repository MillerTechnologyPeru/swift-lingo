import Testing
import BinaryParsing
import LingoAST

@testable import LingoBytecode

/// Assembles a minimal handler + script chunk from hand-encoded bytecode and
/// decompiles it, so each fixture below only needs to state its bytes and
/// name table.
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

@Test(
    arguments: [
        (UInt8(0x05), BinaryOperator.add),
        (UInt8(0x06), BinaryOperator.subtract),
        (UInt8(0x04), BinaryOperator.multiply),
        (UInt8(0x07), BinaryOperator.divide)
    ])
func decompileArithmeticAssignment(opcodeByte: UInt8, expectedOperator: BinaryOperator) throws {
    // global a, b, x
    // x = a <op> b
    let bytes: [UInt8] = [
        0x49, 0x00,  // GetGlobal a
        0x49, 0x01,  // GetGlobal b
        opcodeByte,  // <op>
        0x4f, 0x02,  // SetGlobal x
        0x01  // Ret
    ]
    let statements = try decompiledStatements(bytes: bytes, names: ["a", "b", "x"])

    #expect(
        statements == [
            .assignment(
                target: .identifier("x"),
                value: .binaryOperation(
                    left: .identifier("a"), operator: expectedOperator, right: .identifier("b")),
                syntax: .dot)
        ])
}

@Test func decompilePropertyGet() throws {
    // global obj, x
    // x = obj.prop
    let bytes: [UInt8] = [
        0x49, 0x00,  // GetGlobal obj
        0x61, 0x01,  // GetObjProp prop
        0x4f, 0x02,  // SetGlobal x
        0x01  // Ret
    ]
    let statements = try decompiledStatements(bytes: bytes, names: ["obj", "prop", "x"])

    #expect(
        statements == [
            .assignment(
                target: .identifier("x"),
                value: .propertyAccess(target: .identifier("obj"), property: "prop", syntax: .dot),
                syntax: .dot)
        ])
}

@Test func decompilePropertySet() throws {
    // global obj
    // obj.prop = 5
    let bytes: [UInt8] = [
        0x49, 0x00,  // GetGlobal obj
        0x41, 0x05,  // PushInt8 5
        0x62, 0x01,  // SetObjProp prop
        0x01  // Ret
    ]
    let statements = try decompiledStatements(bytes: bytes, names: ["obj", "prop"])

    #expect(
        statements == [
            .assignment(
                target: .propertyAccess(target: .identifier("obj"), property: "prop", syntax: .dot),
                value: .integer(5),
                syntax: .dot)
        ])
}

@Test func decompileLocalHandlerCall() throws {
    // global x
    // x = add(1, 2)
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
    let statements = try decompiledStatements(bytes: bytes, names: ["x", "add"], handlers: [addHandler])

    #expect(
        statements == [
            .assignment(
                target: .identifier("x"),
                value: .call(name: "add", args: .argList([.integer(1), .integer(2)])),
                syntax: .dot)
        ])
}

@Test func decompileRepeatWhileLoop() throws {
    // repeat while x
    // end repeat
    let bytes: [UInt8] = [
        0x49, 0x00,  // 0: GetGlobal x
        0x55, 0x04,  // 2: JmpIfZ -> pos 6 (end of loop)
        0x54, 0x04,  // 4: EndRepeat -> pos 0 (recheck condition)
        0x01  // 6: Ret
    ]
    let statements = try decompiledStatements(bytes: bytes, names: ["x"])

    #expect(statements == [.repeatWhile(condition: .identifier("x"), body: [])])
}
