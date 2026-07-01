import Testing
@testable import LingoBytecode

@Test func allOpCodesRoundTrip() {
    #expect(OpCode.allCases.count == 77)
    for opcode in OpCode.allCases {
        #expect(OpCode(rawValue: opcode.rawValue) == opcode)
    }
}

@Test func knownOpcodeRawValues() {
    #expect(OpCode.invalid.rawValue == 0x00)
    #expect(OpCode.ret.rawValue == 0x01)
    #expect(OpCode.pushZero.rawValue == 0x03)
    #expect(OpCode.add.rawValue == 0x05)
    #expect(OpCode.callJavaScript.rawValue == 0x26)
    #expect(OpCode.pushInt8.rawValue == 0x41)
    #expect(OpCode.pushArgListNoRet.rawValue == 0x42)
    #expect(OpCode.getLocal.rawValue == 0x4c)
    #expect(OpCode.jmp.rawValue == 0x53)
    #expect(OpCode.put.rawValue == 0x59)
    #expect(OpCode.objCall.rawValue == 0x67)
    #expect(OpCode.pushInt16.rawValue == 0x6e)
    #expect(OpCode.pushFloat32.rawValue == 0x71)
    #expect(OpCode.newObj.rawValue == 0x73)
}
