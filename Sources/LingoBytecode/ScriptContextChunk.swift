import BinaryParsing

public struct ScriptContextMapEntry: Equatable, Sendable {
    public var unknown0: UInt32
    public var sectionId: Int32
    public var unknown1: UInt16
    public var unknown2: UInt16

    public init(parsing input: inout ParserSpan) throws(any Error) {
        unknown0 = try UInt32(parsingBigEndian: &input)
        sectionId = try Int32(parsingBigEndian: &input)
        unknown1 = try UInt16(parsingBigEndian: &input)
        unknown2 = try UInt16(parsingBigEndian: &input)
    }
}

public struct ScriptContextChunk: Equatable, Sendable {
    public var entryCount: UInt32
    public var entryCount2: UInt32
    public var entriesOffset: Int
    public var lnamSectionId: UInt32
    public var validCount: UInt16
    public var flags: UInt16
    public var freePointer: UInt16
    public var sectionMap: [ScriptContextMapEntry]

    public init(
        entryCount: UInt32,
        entryCount2: UInt32,
        entriesOffset: Int,
        lnamSectionId: UInt32,
        validCount: UInt16,
        flags: UInt16,
        freePointer: UInt16,
        sectionMap: [ScriptContextMapEntry]
    ) {
        self.entryCount = entryCount
        self.entryCount2 = entryCount2
        self.entriesOffset = entriesOffset
        self.lnamSectionId = lnamSectionId
        self.validCount = validCount
        self.flags = flags
        self.freePointer = freePointer
        self.sectionMap = sectionMap
    }

    public static func read(from input: borrowing ParserSpan) throws(any Error) -> ScriptContextChunk {
        return try input.withUnsafeBytes { rawBuffer in
            var headerSpan = unsafe ParserSpan(_unsafeBytes: UnsafeRawBufferPointer(
                rebasing: rawBuffer[input.startPosition..<rawBuffer.count]))
            let _ = try UInt32(parsingBigEndian: &headerSpan)
            let _ = try UInt32(parsingBigEndian: &headerSpan)
            let entryCount = try UInt32(parsingBigEndian: &headerSpan)
            let entryCount2 = try UInt32(parsingBigEndian: &headerSpan)
            let entriesOffset = Int(try UInt16(parsingBigEndian: &headerSpan))
            let _ = try UInt16(parsingBigEndian: &headerSpan)
            let _ = try UInt32(parsingBigEndian: &headerSpan)
            let _ = try UInt32(parsingBigEndian: &headerSpan)
            let _ = try UInt32(parsingBigEndian: &headerSpan)
            let lnamSectionId = try UInt32(parsingBigEndian: &headerSpan)
            let validCount = try UInt16(parsingBigEndian: &headerSpan)
            let flags = try UInt16(parsingBigEndian: &headerSpan)
            let freePointer = try UInt16(parsingBigEndian: &headerSpan)

            let offsetInBuffer = entriesOffset - input.startPosition
            guard offsetInBuffer >= 0, offsetInBuffer < rawBuffer.count else {
                throw LingoBytecodeError.invalidOffset(entriesOffset)
            }
            var entriesSpan = unsafe ParserSpan(_unsafeBytes: UnsafeRawBufferPointer(
                rebasing: rawBuffer[offsetInBuffer..<rawBuffer.count]))

            var sectionMap: [ScriptContextMapEntry] = []
            sectionMap.reserveCapacity(Int(entryCount))
            for _ in 0..<entryCount {
                let entry = try ScriptContextMapEntry(parsing: &entriesSpan)
                sectionMap.append(entry)
            }

            return ScriptContextChunk(
                entryCount: entryCount,
                entryCount2: entryCount2,
                entriesOffset: entriesOffset,
                lnamSectionId: lnamSectionId,
                validCount: validCount,
                flags: flags,
                freePointer: freePointer,
                sectionMap: sectionMap
            )
        }
    }
}
