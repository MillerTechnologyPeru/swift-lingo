import BinaryParsing

public struct Bytecode: Equatable, Sendable {
    public var opcode: OpCode
    public var obj: Int64
    public var pos: Int

    public init(parsing input: inout ParserSpan) throws(any Error) {
        let pos = input.startPosition
        let opByte = try UInt8(parsing: &input)
        let opcode: OpCode
        if opByte >= 0x40 {
            let normalized = 0x40 + (opByte % 0x40)
            guard let parsed = OpCode(rawValue: normalized) else {
                throw LingoBytecodeError.unknownOpcode(opByte)
            }
            opcode = parsed
        } else {
            guard let parsed = OpCode(rawValue: opByte) else {
                throw LingoBytecodeError.unknownOpcode(opByte)
            }
            opcode = parsed
        }
        let obj: Int64
        switch opByte {
        case 0x00...0x3F:
            obj = 0
        case 0x40...0x7F:
            if opcode == .pushInt8 || opcode == .pushInt16 {
                obj = Int64(try Int8(parsing: &input))
            } else {
                obj = Int64(try UInt8(parsing: &input))
            }
        default:
            if opcode == .pushInt8 || opcode == .pushInt16 {
                obj = Int64(try Int16(parsingBigEndian: &input))
            } else {
                obj = Int64(try UInt16(parsingBigEndian: &input))
            }
        }
        self.opcode = opcode
        self.obj = obj
        self.pos = pos
    }
}
