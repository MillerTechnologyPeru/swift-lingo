import Testing
import BinaryParsing
@testable import LingoBytecode

@Test func scriptContextMapEntryLayout() throws {
    let bytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x01,  // unknown0 = 1
        0x00, 0x00, 0x00, 0x02,  // sectionId = 2
        0x00, 0x03,  // unknown1 = 3
        0x00, 0x04  // unknown2 = 4
    ]
    let entry = try bytes.withParserSpan { span in
        try ScriptContextMapEntry(parsing: &span)
    }
    #expect(entry.unknown0 == 1)
    #expect(entry.sectionId == 2)
    #expect(entry.unknown1 == 3)
    #expect(entry.unknown2 == 4)
}

@Test func scriptContextChunkLayout() throws {
    let bytes: [UInt8] = [
        // header (14 fields, 42 bytes total)
        0x00, 0x00, 0x00, 0x00,  // unknown0
        0x00, 0x00, 0x00, 0x00,  // unknown1
        0x00, 0x00, 0x00, 0x02,  // entryCount = 2
        0x00, 0x00, 0x00, 0x02,  // entryCount2 = 2
        0x00, 0x2A,  // entriesOffset = 42
        0x00, 0x00,  // unknown2
        0x00, 0x00, 0x00, 0x00,  // unknown3
        0x00, 0x00, 0x00, 0x00,  // unknown4
        0x00, 0x00, 0x00, 0x00,  // unknown5
        0x00, 0x00, 0x00, 0x0A,  // lnamSectionId = 10
        0x00, 0x01,  // validCount = 1
        0x00, 0x00,  // flags = 0
        0x00, 0x00,  // freePointer = 0
        // entry 1 (immediately follows header at offset 42)
        0x00, 0x00, 0x00, 0x01,
        0xFF, 0xFF, 0xFF, 0xFF,
        0x00, 0x0A,
        0x00, 0x0B,
        // entry 2
        0x00, 0x00, 0x00, 0x02,
        0xFF, 0xFF, 0xFF, 0xFE,
        0x00, 0x0C,
        0x00, 0x0D
    ]
    let chunk = try [UInt8](bytes).withParserSpan { span in
        try ScriptContextChunk.read(from: span)
    }
    #expect(chunk.entryCount == 2)
    #expect(chunk.lnamSectionId == 10)
    #expect(chunk.sectionMap.count == 2)
    #expect(chunk.sectionMap[0].unknown0 == 1)
    #expect(chunk.sectionMap[0].sectionId == -1)
    #expect(chunk.sectionMap[1].unknown0 == 2)
    #expect(chunk.sectionMap[1].sectionId == -2)
}

@Test func scriptContextChunkWithNoEntriesAtChunkEnd() throws {
    // A cast with zero scripts stores entryCount == 0 and entriesOffset
    // pointing exactly one-past-the-end of the chunk (42, the header's own
    // size, with no entries following). That's a valid empty section map,
    // not an out-of-range offset, since nothing is ever read from it.
    let bytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x00,  // unknown0
        0x00, 0x00, 0x00, 0x00,  // unknown1
        0x00, 0x00, 0x00, 0x00,  // entryCount = 0
        0x00, 0x00, 0x00, 0x00,  // entryCount2 = 0
        0x00, 0x2A,  // entriesOffset = 42 (== chunk length)
        0x00, 0x00,  // unknown2
        0x00, 0x00, 0x00, 0x00,  // unknown3
        0x00, 0x00, 0x00, 0x00,  // unknown4
        0x00, 0x00, 0x00, 0x00,  // unknown5
        0x00, 0x00, 0x00, 0x0A,  // lnamSectionId = 10
        0x00, 0x00,  // validCount = 0
        0x00, 0x00,  // flags = 0
        0x00, 0x00  // freePointer = 0
    ]
    let chunk = try [UInt8](bytes).withParserSpan { span in
        try ScriptContextChunk.read(from: span)
    }
    #expect(chunk.entryCount == 0)
    #expect(chunk.sectionMap.isEmpty)
}
