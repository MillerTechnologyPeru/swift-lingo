import Testing
import BinaryParsing
@testable import LingoBytecode

@Test func singleByteOpcodeDecodesWithNoOperand() throws {
    let bc = try [UInt8]([0x05]).withParserSpan { span in
        try Bytecode(parsing: &span)
    }
    #expect(bc.opcode == .add)
    #expect(bc.obj == 0)
    #expect(bc.pos == 0)
}

@Test func twoByteOpcodeDecodesOneByteOperand() throws {
    let bc = try [UInt8]([0x41, 0x2A]).withParserSpan { span in
        try Bytecode(parsing: &span)
    }
    #expect(bc.opcode == .pushInt8)
    #expect(bc.obj == 42)
    #expect(bc.pos == 0)
}

@Test func threeByteOpcodeDecodesTwoByteOperand() throws {
    let bc = try [UInt8]([0xAE, 0x01, 0x00]).withParserSpan { span in
        try Bytecode(parsing: &span)
    }
    #expect(bc.opcode == .pushInt16)
    #expect(bc.obj == 256)
    #expect(bc.pos == 0)
}

@Test func unknownOpcodeThrows() throws {
    #expect(throws: LingoBytecodeError.self) {
        try [UInt8]([0xFF]).withParserSpan { span in
            _ = try Bytecode(parsing: &span)
        }
    }
}

@Test func multipleBytecodesInStream() throws {
    let bc = try [UInt8]([0x41, 0x01, 0x41, 0x02, 0x05]).withParserSpan { span in
        let first = try Bytecode(parsing: &span)
        let second = try Bytecode(parsing: &span)
        let third = try Bytecode(parsing: &span)
        return [first, second, third]
    }
    #expect(bc[0].opcode == .pushInt8)
    #expect(bc[0].obj == 1)
    #expect(bc[0].pos == 0)
    #expect(bc[1].opcode == .pushInt8)
    #expect(bc[1].obj == 2)
    #expect(bc[1].pos == 2)
    #expect(bc[2].opcode == .add)
    #expect(bc[2].obj == 0)
    #expect(bc[2].pos == 4)
}
