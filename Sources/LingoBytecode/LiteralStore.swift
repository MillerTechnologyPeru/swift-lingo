import Foundation
import BinaryParsing

public enum LiteralType: UInt32, Equatable, Sendable {
    case invalid = 0
    case string = 1
    case int = 4
    case float = 9
    case javascript = 11
}

public enum LiteralValue: Equatable, Sendable {
    case invalid
    case string(String)
    case int(Int32)
    case double(Double)
    case javascript([UInt8])
}

public struct LiteralStoreRecord: Equatable, Sendable {
    public var literalType: LiteralType
    public var offset: Int

    public init(parsing input: inout ParserSpan) throws(any Error) {
        let typeId = try UInt32(parsingBigEndian: &input)
        guard let literalType = LiteralType(rawValue: typeId) else {
            throw LingoBytecodeError.unknownLiteralType(typeId)
        }
        self.literalType = literalType
        self.offset = Int(try UInt32(parsingBigEndian: &input))
    }
}

public struct LiteralStore: Equatable, Sendable {
    public var record: LiteralStoreRecord
    public var data: LiteralValue

    public init(record: LiteralStoreRecord, data: LiteralValue) {
        self.record = record
        self.data = data
    }

    public init(parsing recordSpan: inout ParserSpan, dataSpan: borrowing ParserSpan) throws(any Error) {
        let record = try LiteralStoreRecord(parsing: &recordSpan)
        let data = try Self.readData(from: dataSpan, record: record)
        self.record = record
        self.data = data
    }

    public static func readData(
        from dataSpan: borrowing ParserSpan,
        record: LiteralStoreRecord
    ) throws(any Error) -> LiteralValue {
        if record.literalType == .int {
            return .int(Int32(bitPattern: UInt32(record.offset)))
        }
        return try dataSpan.withUnsafeBytes { rawBuffer in
            let offsetInBuffer = record.offset
            guard offsetInBuffer >= 0, offsetInBuffer < rawBuffer.count else {
                throw LingoBytecodeError.invalidOffset(record.offset)
            }
            var literalSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[offsetInBuffer..<rawBuffer.count]))
            let length = Int(try UInt32(parsingBigEndian: &literalSpan))
            switch record.literalType {
            case .string:
                let stringByteCount = max(0, length - 1)
                let stringEnd = offsetInBuffer + 4 + stringByteCount
                guard stringEnd <= rawBuffer.count else {
                    throw LingoBytecodeError.invalidOffset(record.offset)
                }
                var stringSpan = unsafe ParserSpan(
                    _unsafeBytes: UnsafeRawBufferPointer(
                        rebasing: rawBuffer[offsetInBuffer + 4..<stringEnd]))
                let stringBytes = try [UInt8](parsing: &stringSpan, byteCount: stringByteCount)
                if let decoded = String(bytes: stringBytes, encoding: .ascii) {
                    return .string(decoded)
                }
                return .invalid
            case .float:
                if length == 8 {
                    let doubleEnd = offsetInBuffer + 12
                    guard doubleEnd <= rawBuffer.count else {
                        throw LingoBytecodeError.invalidOffset(record.offset)
                    }
                    var doubleSpan = unsafe ParserSpan(
                        _unsafeBytes: UnsafeRawBufferPointer(
                            rebasing: rawBuffer[offsetInBuffer + 4..<doubleEnd]))
                    let uint64 = try UInt64(parsingBigEndian: &doubleSpan)
                    return .double(Double(bitPattern: uint64))
                }
                return .double(0.0)
            case .javascript:
                let jsEnd = offsetInBuffer + 4 + length
                guard jsEnd <= rawBuffer.count else {
                    throw LingoBytecodeError.invalidOffset(record.offset)
                }
                var jsSpan = unsafe ParserSpan(
                    _unsafeBytes: UnsafeRawBufferPointer(
                        rebasing: rawBuffer[offsetInBuffer + 4..<jsEnd]))
                let jsBytes = try [UInt8](parsing: &jsSpan, byteCount: length)
                return .javascript(jsBytes)
            default:
                return .invalid
            }
        }
    }
}
