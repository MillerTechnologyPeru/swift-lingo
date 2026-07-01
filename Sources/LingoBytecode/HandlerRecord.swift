import BinaryParsing

public struct HandlerRecord: Equatable, Sendable {
    public var nameId: UInt16
    public var vectorPos: UInt16
    public var compiledLen: Int
    public var compiledOffset: Int
    public var argumentCount: UInt16
    public var argumentOffset: Int
    public var localsCount: UInt16
    public var localsOffset: Int
    public var globalsCount: UInt16
    public var globalsOffset: Int
    public var unknown1: UInt32
    public var unknown2: UInt16
    public var lineCount: UInt16
    public var lineOffset: UInt32

    public init(parsing input: inout ParserSpan) throws(any Error) {
        nameId = try UInt16(parsingBigEndian: &input)
        vectorPos = try UInt16(parsingBigEndian: &input)
        compiledLen = Int(try UInt32(parsingBigEndian: &input))
        compiledOffset = Int(try UInt32(parsingBigEndian: &input))
        argumentCount = try UInt16(parsingBigEndian: &input)
        argumentOffset = Int(try UInt32(parsingBigEndian: &input))
        localsCount = try UInt16(parsingBigEndian: &input)
        localsOffset = Int(try UInt32(parsingBigEndian: &input))
        globalsCount = try UInt16(parsingBigEndian: &input)
        globalsOffset = Int(try UInt32(parsingBigEndian: &input))
        unknown1 = try UInt32(parsingBigEndian: &input)
        unknown2 = try UInt16(parsingBigEndian: &input)
        lineCount = try UInt16(parsingBigEndian: &input)
        lineOffset = try UInt32(parsingBigEndian: &input)
    }
}
