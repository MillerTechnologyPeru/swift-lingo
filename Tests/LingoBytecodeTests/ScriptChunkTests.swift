import Testing
import BinaryParsing
@testable import LingoBytecode

private func be16(_ value: UInt16) -> [UInt8] {
    [UInt8(value >> 8), UInt8(value & 0xFF)]
}

private func be32(_ value: UInt32) -> [UInt8] {
    [
        UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
    ]
}

@Test func scriptChunkParsesMinimalScript() throws {
    // Layout (absolute byte offsets within the Lscr body):
    //   0-91    fixed header
    //   92-133  one HandlerRecord (42 bytes)
    //   134-141 one LiteralStoreRecord (8 bytes, Int type)
    //   142-147 the handler's bytecode stream (6 bytes)
    let handlersOffset: UInt32 = 92
    let literalsOffset: UInt32 = 134
    let compiledOffset: UInt32 = 142
    let literalsDataOffset: UInt32 = 148

    var bytes: [UInt8] = []
    bytes += [UInt8](repeating: 0, count: 8)  // 0: unused
    bytes += be32(0)  // 8: totalLength
    bytes += be32(0)  // 12: totalLength2
    bytes += be16(0)  // 16: headerLength
    bytes += be16(7)  // 18: scriptNumber = 7
    bytes += be16(0)  // 20: unk20
    bytes += be16(0)  // 22: parentNumber
    bytes += [UInt8](repeating: 0, count: 14)  // 24: unused, up to jmp(38)
    bytes += be32(0)  // 38: scriptFlags
    bytes += be16(0)  // 42: unk42
    bytes += be32(0)  // 44: castId
    bytes += be16(0)  // 48: factoryNameId
    bytes += be16(0)  // 50: handlerVectorsCount
    bytes += be32(0)  // 52: handlerVectorsOffset
    bytes += be32(0)  // 56: handlerVectorsSize
    bytes += be16(0)  // 60: propertiesCount
    bytes += be32(0)  // 62: propertiesOffset
    bytes += be16(0)  // 66: globalsCount
    bytes += be32(0)  // 68: globalsOffset
    bytes += be16(1)  // 72: handlersCount = 1
    bytes += be32(handlersOffset)  // 74: handlersOffset
    bytes += be16(1)  // 78: literalsCount = 1
    bytes += be32(literalsOffset)  // 80: literalsOffset
    bytes += be32(0)  // 84: literalsDataCount
    bytes += be32(literalsDataOffset)  // 88: literalsDataOffset
    #expect(bytes.count == 92)

    // HandlerRecord (42 bytes)
    bytes += be16(1)  // nameId = 1
    bytes += be16(0)  // vectorPos
    bytes += be32(6)  // compiledLen = 6 bytes
    bytes += be32(compiledOffset)  // compiledOffset
    bytes += be16(0)  // argumentCount
    bytes += be32(0)  // argumentOffset
    bytes += be16(0)  // localsCount
    bytes += be32(0)  // localsOffset
    bytes += be16(0)  // globalsCount
    bytes += be32(0)  // globalsOffset
    bytes += be32(0)  // unknown1
    bytes += be16(0)  // unknown2
    bytes += be16(0)  // lineCount
    bytes += be32(0)  // lineOffset
    #expect(bytes.count == 134)

    // LiteralStoreRecord (8 bytes): Int literal, value 42
    bytes += be32(4)  // literalType = .int
    bytes += be32(42)  // offset (the literal value itself, for ints)
    #expect(bytes.count == 142)

    // Bytecode stream: on foo -- return 1 + 2 -- end
    bytes += [0x41, 0x01]  // PushInt8 1
    bytes += [0x41, 0x02]  // PushInt8 2
    bytes += [0x05]  // Add
    bytes += [0x01]  // Ret
    #expect(bytes.count == 148)

    let chunk = try bytes.withParserSpan { span in
        try ScriptChunk.read(from: span)
    }

    #expect(chunk.scriptNumber == 7)
    #expect(chunk.literals == [.int(42)])
    #expect(chunk.propertyNameIDs.isEmpty)
    #expect(chunk.propertyDefaults.isEmpty)
    #expect(chunk.handlers.count == 1)

    let handler = chunk.handlers[0]
    #expect(handler.nameId == 1)
    #expect(handler.argumentNameIds.isEmpty)
    #expect(handler.localNameIds.isEmpty)
    #expect(handler.globalNameIds.isEmpty)

    // Confirms the embedded bytecode stream round-trips through the same
    // decoder Step 3 tests exercise in isolation, not just when standalone.
    #expect(handler.bytecodeArray.map(\.opcode) == [.pushInt8, .pushInt8, .add, .ret])
    #expect(handler.bytecodeArray.map(\.obj) == [1, 2, 0, 0])
    #expect(handler.bytecodeArray.map(\.pos) == [0, 2, 4, 5])
}

@Test func scriptChunkMapsPropertyDefaultsFromLiterals() throws {
    // Same layout as above, but with one property whose default comes from
    // the (only) literal, and zero handlers.
    let literalsOffset: UInt32 = 92
    let propertiesOffset: UInt32 = 100  // placed right after the literal record

    var bytes: [UInt8] = []
    bytes += [UInt8](repeating: 0, count: 8)
    bytes += be32(0)  // totalLength
    bytes += be32(0)  // totalLength2
    bytes += be16(0)  // headerLength
    bytes += be16(9)  // scriptNumber = 9
    bytes += be16(0)  // unk20
    bytes += be16(0)  // parentNumber
    bytes += [UInt8](repeating: 0, count: 14)
    bytes += be32(0)  // scriptFlags
    bytes += be16(0)  // unk42
    bytes += be32(0)  // castId
    bytes += be16(0)  // factoryNameId
    bytes += be16(0)  // handlerVectorsCount
    bytes += be32(0)  // handlerVectorsOffset
    bytes += be32(0)  // handlerVectorsSize
    bytes += be16(1)  // propertiesCount = 1
    bytes += be32(propertiesOffset)  // propertiesOffset
    bytes += be16(0)  // globalsCount
    bytes += be32(0)  // globalsOffset
    bytes += be16(0)  // handlersCount = 0
    bytes += be32(0)  // handlersOffset
    bytes += be16(1)  // literalsCount = 1
    bytes += be32(literalsOffset)  // literalsOffset
    bytes += be32(0)  // literalsDataCount
    bytes += be32(literalsOffset + 8)  // literalsDataOffset (unused: Int literal)
    #expect(bytes.count == 92)

    bytes += be32(4)  // literalType = .int
    bytes += be32(5)  // literal value = 5
    #expect(bytes.count == 100)

    bytes += be16(20)  // propertyNameIDs[0] = 20
    #expect(bytes.count == 102)

    let chunk = try bytes.withParserSpan { span in
        try ScriptChunk.read(from: span)
    }

    #expect(chunk.scriptNumber == 9)
    #expect(chunk.propertyNameIDs == [20])
    #expect(chunk.propertyDefaults == [20: .int(5)])
    #expect(chunk.handlers.isEmpty)
}
