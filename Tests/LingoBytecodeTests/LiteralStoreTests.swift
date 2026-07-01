import Testing
import BinaryParsing
@testable import LingoBytecode

@Test func stringLiteralDecodes() throws {
    let recordBytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x01,  // type = String
        0x00, 0x00, 0x00, 0x00  // offset = 0
    ]
    let dataBytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x06,  // length = 6
        0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x00  // "hello" + null
    ]
    let bytes = recordBytes + dataBytes
    let store = try bytes.withUnsafeBytes { rawBuffer in
        var recordSpan = unsafe ParserSpan(_unsafeBytes: rawBuffer)
        let record = try LiteralStoreRecord(parsing: &recordSpan)
        let data = try LiteralStore.readData(from: recordSpan, record: record)
        return LiteralStore(record: record, data: data)
    }
    #expect(store.record.literalType == .string)
    #expect(store.data == .string("hello"))
}

@Test func intLiteralDecodes() throws {
    let recordBytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x04,  // type = Int
        0x00, 0x00, 0x01, 0x2C  // offset = 300
    ]
    let store = try recordBytes.withUnsafeBytes { rawBuffer in
        var recordSpan = unsafe ParserSpan(_unsafeBytes: rawBuffer)
        let record = try LiteralStoreRecord(parsing: &recordSpan)
        return LiteralStore(record: record, data: .int(Int32(record.offset)))
    }
    #expect(store.record.literalType == .int)
    #expect(store.data == .int(300))
}

@Test func floatLiteralDecodes() throws {
    let recordBytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x09,  // type = Float
        0x00, 0x00, 0x00, 0x00  // offset = 0
    ]
    let dataBytes: [UInt8] = [
        0x00, 0x00, 0x00, 0x08,  // length = 8
        0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  // double 1.0
    ]
    let bytes = recordBytes + dataBytes
    let store = try bytes.withUnsafeBytes { rawBuffer in
        var recordSpan = unsafe ParserSpan(_unsafeBytes: rawBuffer)
        let record = try LiteralStoreRecord(parsing: &recordSpan)
        let data = try LiteralStore.readData(from: recordSpan, record: record)
        return LiteralStore(record: record, data: data)
    }
    #expect(store.record.literalType == .float)
    #expect(store.data == .double(1.0))
}
