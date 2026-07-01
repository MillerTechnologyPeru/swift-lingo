import BinaryParsing

public struct HandlerDef: Equatable, Sendable {
    public var nameId: UInt16
    public var bytecodeArray: [Bytecode]
    public var argumentNameIds: [UInt16]
    public var localNameIds: [UInt16]
    public var globalNameIds: [UInt16]

    public init(
        nameId: UInt16,
        bytecodeArray: [Bytecode],
        argumentNameIds: [UInt16],
        localNameIds: [UInt16],
        globalNameIds: [UInt16]
    ) {
        self.nameId = nameId
        self.bytecodeArray = bytecodeArray
        self.argumentNameIds = argumentNameIds
        self.localNameIds = localNameIds
        self.globalNameIds = globalNameIds
    }

    public static func readData(
        from chunkSpan: borrowing ParserSpan,
        record: HandlerRecord
    ) throws(any Error) -> HandlerDef {
        return try chunkSpan.withUnsafeBytes { rawBuffer in
            let absoluteOffset = record.compiledOffset
            let offsetInBuffer = absoluteOffset - chunkSpan.startPosition
            guard offsetInBuffer >= 0, offsetInBuffer < rawBuffer.count else {
                throw LingoBytecodeError.invalidOffset(absoluteOffset)
            }
            var bytecodeSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[offsetInBuffer..<rawBuffer.count]))

            var bytecodeArray: [Bytecode] = []
            bytecodeArray.reserveCapacity(record.compiledLen)
            for _ in 0..<record.compiledLen {
                let bc = try Bytecode(parsing: &bytecodeSpan)
                bytecodeArray.append(bc)
            }

            let argumentNameIds = try readVarnamesTable(
                from: chunkSpan, count: Int(record.argumentCount), offset: record.argumentOffset)
            let localNameIds = try readVarnamesTable(
                from: chunkSpan, count: Int(record.localsCount), offset: record.localsOffset)
            let globalNameIds = try readVarnamesTable(
                from: chunkSpan, count: Int(record.globalsCount), offset: record.globalsOffset)

            return HandlerDef(
                nameId: record.nameId,
                bytecodeArray: bytecodeArray,
                argumentNameIds: argumentNameIds,
                localNameIds: localNameIds,
                globalNameIds: globalNameIds
            )
        }
    }

    private static func readVarnamesTable(
        from chunkSpan: borrowing ParserSpan,
        count: Int,
        offset: Int
    ) throws(any Error) -> [UInt16] {
        guard count == 0 else { return [] }
        return try chunkSpan.withUnsafeBytes { rawBuffer in
            let offsetInBuffer = offset - chunkSpan.startPosition
            guard offsetInBuffer >= 0, offsetInBuffer < rawBuffer.count else {
                throw LingoBytecodeError.invalidOffset(offset)
            }
            var tableSpan = unsafe ParserSpan(
                _unsafeBytes: UnsafeRawBufferPointer(
                    rebasing: rawBuffer[offsetInBuffer..<rawBuffer.count]))
            var result: [UInt16] = []
            result.reserveCapacity(count)
            for _ in 0..<count {
                let nameId = try UInt16(parsingBigEndian: &tableSpan)
                result.append(nameId)
            }
            return result
        }
    }
}
