import Testing
import BinaryParsing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

@Test func emptyHandlerReturnsVoid() throws {
    let handler = HandlerDef(
        nameId: 0, bytecodeArray: [], argumentNameIds: [], localNameIds: [], globalNameIds: [])
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: [], handlers: [handler], propertyNameIDs: [], propertyDefaults: [:])

    let result = try LingoVM.call(handler: handler, chunk: chunk, names: [], version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
}

@Test func unrecognizedOpcodeThrows() throws {
    // Every real opcode is handled as of Step 10's full sweep — `.invalid`
    // (0x00) is the one value that should permanently throw, since it's
    // explicitly a placeholder/never-emitted marker, not a real instruction.
    let bytecode = try [UInt8]([0x00]).withParserSpan { span in
        try Bytecode(parsing: &span)
    }
    let handler = HandlerDef(
        nameId: 0, bytecodeArray: [bytecode], argumentNameIds: [], localNameIds: [], globalNameIds: [])
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: [], handlers: [handler], propertyNameIDs: [], propertyDefaults: [:])

    #expect(throws: LingoVMError.unknownOpcode(.invalid)) {
        try LingoVM.call(handler: handler, chunk: chunk, names: [], version: 500)
    }
}
