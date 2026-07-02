import BinaryParsing

public struct ScriptChunk: Equatable, Sendable {
    public var scriptNumber: UInt16
    public var literals: [LiteralValue]
    public var handlers: [HandlerDef]
    public var propertyNameIDs: [UInt16]
    public var propertyDefaults: [UInt16: LiteralValue]

    public init(
        scriptNumber: UInt16,
        literals: [LiteralValue],
        handlers: [HandlerDef],
        propertyNameIDs: [UInt16],
        propertyDefaults: [UInt16: LiteralValue]
    ) {
        self.scriptNumber = scriptNumber
        self.literals = literals
        self.handlers = handlers
        self.propertyNameIDs = propertyNameIDs
        self.propertyDefaults = propertyDefaults
    }

    public static func read(from input: borrowing ParserSpan) throws(any Error) -> ScriptChunk {
        try input.withUnsafeBytes { rawBuffer in
            var headerSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[(8 - input.startPosition)..<rawBuffer.count]))
            let _ = try UInt32(parsingBigEndian: &headerSpan)  // totalLength
            let _ = try UInt32(parsingBigEndian: &headerSpan)  // totalLength2
            let _ = try UInt16(parsingBigEndian: &headerSpan)  // headerLength
            let scriptNumber = try UInt16(parsingBigEndian: &headerSpan)
            let _ = try UInt16(parsingBigEndian: &headerSpan)  // unk20
            let _ = try UInt16(parsingBigEndian: &headerSpan)  // parentNumber

            var flagsSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[(38 - input.startPosition)..<rawBuffer.count]))
            let _ = try UInt32(parsingBigEndian: &flagsSpan)  // scriptFlags
            let _ = try UInt16(parsingBigEndian: &flagsSpan)  // unk42
            let _ = try UInt32(parsingBigEndian: &flagsSpan)  // castId
            let _ = try UInt16(parsingBigEndian: &flagsSpan)  // factoryNameId
            let _ = try UInt16(parsingBigEndian: &flagsSpan)  // handlerVectorsCount
            let _ = try UInt32(parsingBigEndian: &flagsSpan)  // handlerVectorsOffset
            let _ = try UInt32(parsingBigEndian: &flagsSpan)  // handlerVectorsSize
            let propertiesCount = Int(try UInt16(parsingBigEndian: &flagsSpan))
            let propertiesOffset = Int(try UInt32(parsingBigEndian: &flagsSpan))
            let globalsCount = Int(try UInt16(parsingBigEndian: &flagsSpan))
            let globalsOffset = Int(try UInt32(parsingBigEndian: &flagsSpan))
            let handlersCount = Int(try UInt16(parsingBigEndian: &flagsSpan))
            let handlersOffset = Int(try UInt32(parsingBigEndian: &flagsSpan))
            let literalsCount = Int(try UInt16(parsingBigEndian: &flagsSpan))
            let literalsOffset = Int(try UInt32(parsingBigEndian: &flagsSpan))
            let _ = try UInt32(parsingBigEndian: &flagsSpan)  // literalsDataCount
            let literalsDataOffset = Int(try UInt32(parsingBigEndian: &flagsSpan))

            let propertyNameIDs = try Self.readVarnamesTable(
                from: rawBuffer, chunkStart: input.startPosition, count: propertiesCount,
                offset: propertiesOffset)
            // The chunk format includes a global-name table here, but a
            // script's globals are resolved by name at call time elsewhere,
            // so nothing in ScriptChunk consumes this table's contents.
            let _ = try Self.readVarnamesTable(
                from: rawBuffer, chunkStart: input.startPosition, count: globalsCount,
                offset: globalsOffset)

            let handlerRecordsOffsetInBuffer = handlersOffset - input.startPosition
            guard handlerRecordsOffsetInBuffer >= 0, handlerRecordsOffsetInBuffer <= rawBuffer.count
            else {
                throw LingoBytecodeError.invalidOffset(handlersOffset)
            }
            var handlerRecordsSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[handlerRecordsOffsetInBuffer..<rawBuffer.count]))
            var handlerRecords: [HandlerRecord] = []
            handlerRecords.reserveCapacity(handlersCount)
            for _ in 0..<handlersCount {
                handlerRecords.append(try HandlerRecord(parsing: &handlerRecordsSpan))
            }
            let handlers = try handlerRecords.map {
                record throws(any Error) -> HandlerDef in
                try HandlerDef.readData(from: input, record: record)
            }

            let literalRecordsOffsetInBuffer = literalsOffset - input.startPosition
            guard literalRecordsOffsetInBuffer >= 0, literalRecordsOffsetInBuffer <= rawBuffer.count
            else {
                throw LingoBytecodeError.invalidOffset(literalsOffset)
            }
            var literalRecordsSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[literalRecordsOffsetInBuffer..<rawBuffer.count]))
            var literalRecords: [LiteralStoreRecord] = []
            literalRecords.reserveCapacity(literalsCount)
            for _ in 0..<literalsCount {
                literalRecords.append(try LiteralStoreRecord(parsing: &literalRecordsSpan))
            }

            let literalsDataOffsetInBuffer = literalsDataOffset - input.startPosition
            guard literalsDataOffsetInBuffer >= 0, literalsDataOffsetInBuffer <= rawBuffer.count
            else {
                throw LingoBytecodeError.invalidOffset(literalsDataOffset)
            }
            let literalsDataSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[literalsDataOffsetInBuffer..<rawBuffer.count]))

            let hasJavaScript = literalRecords.contains { $0.literalType == .javascript }
            let literals: [LiteralValue]
            if hasJavaScript {
                literals = try Self.readJavaScriptLiterals(
                    from: literalsDataSpan, count: literalsCount)
            } else {
                literals = try literalRecords.map {
                    record throws(any Error) -> LiteralValue in
                    try LiteralStore.readData(from: literalsDataSpan, record: record)
                }
            }

            var propertyDefaults: [UInt16: LiteralValue] = [:]
            for (index, propertyNameID) in propertyNameIDs.enumerated() where index < literals.count {
                if propertyDefaults[propertyNameID] == nil {
                    propertyDefaults[propertyNameID] = literals[index]
                }
            }

            return ScriptChunk(
                scriptNumber: scriptNumber,
                literals: literals,
                handlers: handlers,
                propertyNameIDs: propertyNameIDs,
                propertyDefaults: propertyDefaults
            )
        }
    }

    /// JavaScript `Lscr` chunks store one compiled script in the literal data
    /// area rather than one entry per literal record; every other slot stays
    /// `.invalid`, matching the placeholder records so `literals.count` still
    /// equals `literalsCount`.
    private static func readJavaScriptLiterals(
        from dataSpan: borrowing ParserSpan,
        count: Int
    ) throws(any Error) -> [LiteralValue] {
        try dataSpan.withUnsafeBytes { rawBuffer in
            guard rawBuffer.count >= 4 else {
                throw LingoBytecodeError.invalidOffset(0)
            }
            var span = unsafe ParserSpan(_unsafeBytes: rawBuffer)
            let totalSize = Int(try UInt32(parsingBigEndian: &span))
            let jsBytes = try [UInt8](parsing: &span, byteCount: totalSize)
            var literals: [LiteralValue] = [.javascript(jsBytes)]
            while literals.count < count {
                literals.append(.invalid)
            }
            return literals
        }
    }

    private static func readVarnamesTable(
        from rawBuffer: UnsafeRawBufferPointer,
        chunkStart: Int,
        count: Int,
        offset: Int
    ) throws(any Error) -> [UInt16] {
        guard count > 0 else { return [] }
        let offsetInBuffer = offset - chunkStart
        guard offsetInBuffer >= 0, offsetInBuffer < rawBuffer.count else {
            throw LingoBytecodeError.invalidOffset(offset)
        }
        var span = unsafe ParserSpan(
            _unsafeBytes: UnsafeRawBufferPointer(rebasing: rawBuffer[offsetInBuffer..<rawBuffer.count]))
        var result: [UInt16] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            result.append(try UInt16(parsingBigEndian: &span))
        }
        return result
    }
}
