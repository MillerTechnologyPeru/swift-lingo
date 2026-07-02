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
    // Ret's opcode (0x01) is recognized by the parser but not yet handled by
    // the executor's step loop at this point in the build-out.
    let bytecode = try [UInt8]([0x01]).withParserSpan { span in
        try Bytecode(parsing: &span)
    }
    let handler = HandlerDef(
        nameId: 0, bytecodeArray: [bytecode], argumentNameIds: [], localNameIds: [], globalNameIds: [])
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: [], handlers: [handler], propertyNameIDs: [], propertyDefaults: [:])

    #expect(throws: LingoVMError.unknownOpcode(.ret)) {
        try LingoVM.call(handler: handler, chunk: chunk, names: [], version: 500)
    }
}
