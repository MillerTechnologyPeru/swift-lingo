import Testing
import BinaryParsing
@testable import LingoBytecode

@Test func handlerDefDecodesByteBoundedBytecodeAndVarnameTables() throws {
    // Chunk layout, absolute offsets:
    //   0-1   argument name table (1 entry)
    //   2-3   locals name table (1 entry)
    //   4-7   globals name table (2 entries)
    //   8-13  bytecode stream (6 bytes: PushInt8 1, PushInt8 2, Add, Ret)
    let chunkBytes: [UInt8] = [
        0x00, 0x0A,  // argumentNameIds[0] = 10
        0x00, 0x0B,  // localNameIds[0] = 11
        0x00, 0x0C,  // globalNameIds[0] = 12
        0x00, 0x0D,  // globalNameIds[1] = 13
        0x41, 0x01,  // PushInt8 1
        0x41, 0x02,  // PushInt8 2
        0x05,  // Add
        0x01  // Ret
    ]
    let recordBytes: [UInt8] = [
        0x00, 0x01,  // nameId = 1
        0x00, 0x00,  // vectorPos = 0
        0x00, 0x00, 0x00, 0x06,  // compiledLen = 6
        0x00, 0x00, 0x00, 0x08,  // compiledOffset = 8
        0x00, 0x01,  // argumentCount = 1
        0x00, 0x00, 0x00, 0x00,  // argumentOffset = 0
        0x00, 0x01,  // localsCount = 1
        0x00, 0x00, 0x00, 0x02,  // localsOffset = 2
        0x00, 0x02,  // globalsCount = 2
        0x00, 0x00, 0x00, 0x04,  // globalsOffset = 4
        0x00, 0x00, 0x00, 0x00,  // unknown1
        0x00, 0x00,  // unknown2
        0x00, 0x00,  // lineCount
        0x00, 0x00, 0x00, 0x00  // lineOffset
    ]
    let record = try recordBytes.withParserSpan { span in
        try HandlerRecord(parsing: &span)
    }
    let handler = try chunkBytes.withParserSpan { span in
        try HandlerDef.readData(from: span, record: record)
    }
    #expect(handler.nameId == 1)
    #expect(handler.argumentNameIds == [10])
    #expect(handler.localNameIds == [11])
    #expect(handler.globalNameIds == [12, 13])
    #expect(handler.bytecodeArray.map(\.opcode) == [.pushInt8, .pushInt8, .add, .ret])
    #expect(handler.bytecodeArray.map(\.obj) == [1, 2, 0, 0])
    #expect(handler.bytecodeArray.map(\.pos) == [0, 2, 4, 5])
}

@Test func handlerDefWithNoVarnamesReturnsEmptyTables() throws {
    let chunkBytes: [UInt8] = [0x01]  // Ret
    let recordBytes: [UInt8] = [
        0x00, 0x01,  // nameId = 1
        0x00, 0x00,  // vectorPos = 0
        0x00, 0x00, 0x00, 0x01,  // compiledLen = 1
        0x00, 0x00, 0x00, 0x00,  // compiledOffset = 0
        0x00, 0x00,  // argumentCount = 0
        0x00, 0x00, 0x00, 0x00,  // argumentOffset
        0x00, 0x00,  // localsCount = 0
        0x00, 0x00, 0x00, 0x00,  // localsOffset
        0x00, 0x00,  // globalsCount = 0
        0x00, 0x00, 0x00, 0x00,  // globalsOffset
        0x00, 0x00, 0x00, 0x00,  // unknown1
        0x00, 0x00,  // unknown2
        0x00, 0x00,  // lineCount
        0x00, 0x00, 0x00, 0x00  // lineOffset
    ]
    let record = try recordBytes.withParserSpan { span in
        try HandlerRecord(parsing: &span)
    }
    let handler = try chunkBytes.withParserSpan { span in
        try HandlerDef.readData(from: span, record: record)
    }
    #expect(handler.argumentNameIds.isEmpty)
    #expect(handler.localNameIds.isEmpty)
    #expect(handler.globalNameIds.isEmpty)
    #expect(handler.bytecodeArray.map(\.opcode) == [.ret])
}
