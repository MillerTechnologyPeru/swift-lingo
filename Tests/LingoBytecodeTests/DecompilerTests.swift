import Testing
import BinaryParsing
import LingoAST
@testable import LingoBytecode

@Test func decompileArithmeticInsideStatementCall() throws {
    // on foo
    //   beep(1 + 2)
    // end
    let bytes: [UInt8] = [
        0x41, 0x01,  // PushInt8 1
        0x41, 0x02,  // PushInt8 2
        0x05,  // Add
        0x42, 0x01,  // PushArgListNoRet 1
        0x57, 0x00,  // ExtCall "beep" (name id 0)
        0x01  // Ret
    ]
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
        scriptNumber: 1, literals: [], handlers: [handler], propertyNameIDs: [], propertyDefaults: [:])

    let statements = LingoBytecode.decompile(handler: handler, chunk: chunk, names: ["beep"], version: 500)

    #expect(
        statements == [
            .expressionStatement(
                .functionCall(
                    target: nil, name: "beep",
                    arguments: [
                        .binaryOperation(left: .integer(1), operator: .add, right: .integer(2))
                    ]))
        ])
}

@Test func decompileIfStatementWithElse() throws {
    // on foo
    //   if x then
    //     exit
    //   else
    //     exit
    //   end if
    // end
    //
    // pos  bytes        instruction
    //  0   0x49 0x00    GetGlobal "x"   (name id 0)
    //  2   0x55 0x05    JmpIfZ -> pos 2+5=7 (skip the then-branch to the else-branch)
    //  4   0x01         Exit            (then-branch body)
    //  5   0x53 0x03    Jmp -> pos 5+3=8 (skip the else-branch to the end)
    //  7   0x01         Exit            (else-branch body)
    //  8   0x01         Ret             (end of handler)
    let bytes: [UInt8] = [
        0x49, 0x00,  // 0: GetGlobal x
        0x55, 0x05,  // 2: JmpIfZ
        0x01,  // 4: Exit
        0x53, 0x03,  // 5: Jmp
        0x01,  // 7: Exit (else branch)
        0x01  // 8: Ret
    ]
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
        scriptNumber: 1, literals: [], handlers: [handler], propertyNameIDs: [], propertyDefaults: [:])

    let statements = LingoBytecode.decompile(handler: handler, chunk: chunk, names: ["x"], version: 500)

    #expect(
        statements == [
            .ifStatement(
                condition: .identifier("x"),
                body: [.exit],
                elseBody: [.exit])
        ])
}
