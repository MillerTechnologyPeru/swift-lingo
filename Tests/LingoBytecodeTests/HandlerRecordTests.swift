import Testing
import BinaryParsing
@testable import LingoBytecode

@Test func handlerRecordLayout() throws {
    let bytes: [UInt8] = [
        0x00, 0x01,  // nameId = 1
        0x00, 0x02,  // vectorPos = 2
        0x00, 0x00, 0x00, 0x0A,  // compiledLen = 10
        0x00, 0x00, 0x00, 0x64,  // compiledOffset = 100
        0x00, 0x03,  // argumentCount = 3
        0x00, 0x00, 0x00, 0xC8,  // argumentOffset = 200
        0x00, 0x04,  // localsCount = 4
        0x00, 0x00, 0x01, 0x2C,  // localsOffset = 300
        0x00, 0x05,  // globalsCount = 5
        0x00, 0x00, 0x01, 0x90,  // globalsOffset = 400
        0x00, 0x00, 0x00, 0x00,  // unknown1 = 0
        0x00, 0x06,  // unknown2 = 6
        0x00, 0x07,  // lineCount = 7
        0x00, 0x00, 0x02, 0x58  // lineOffset = 600
    ]
    let record = try bytes.withParserSpan { span in
        try HandlerRecord(parsing: &span)
    }
    #expect(record.nameId == 1)
    #expect(record.vectorPos == 2)
    #expect(record.compiledLen == 10)
    #expect(record.compiledOffset == 100)
    #expect(record.argumentCount == 3)
    #expect(record.argumentOffset == 200)
    #expect(record.localsCount == 4)
    #expect(record.localsOffset == 300)
    #expect(record.globalsCount == 5)
    #expect(record.globalsOffset == 400)
    #expect(record.unknown1 == 0)
    #expect(record.unknown2 == 6)
    #expect(record.lineCount == 7)
    #expect(record.lineOffset == 600)
}
