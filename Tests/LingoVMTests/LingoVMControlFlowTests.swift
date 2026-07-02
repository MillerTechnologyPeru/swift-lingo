import Testing
import LingoRuntime

@testable import LingoVM

@Test func retReturnsTopOfStackAsValue() throws {
    let executor = try makeExecutor(bytes: [0x41, 0x2a, 0x01])  // PushInt8 42, Ret
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(42)))
}

@Test func exitWithNoValueReturnsVoid() throws {
    let executor = try makeExecutor(bytes: [0x01])  // Ret, nothing pushed first
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
}

@Test func jmpIfZSkipsBlockWhenConditionFalse() throws {
    // if 0 then push 99 end if; push 1
    //  0: PushZero
    //  1-2: JmpIfZ -> pos 7 (skip the "then" push)
    //  3-4: PushInt8 99
    //  5-6: Pop 1              (discard the then-block's value)
    //  7-8: PushInt8 1
    //  9: Ret
    let bytes: [UInt8] = [
        0x03,  // 0: PushZero
        0x55, 0x06,  // 1: JmpIfZ -> 1+6=7
        0x41, 0x63,  // 3: PushInt8 99
        0x65, 0x01,  // 5: Pop 1
        0x41, 0x01,  // 7: PushInt8 1
        0x01  // 9: Ret
    ]
    let executor = try makeExecutor(bytes: bytes)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(1)))
}

@Test func jmpIfZTakesBlockWhenConditionTrue() throws {
    // Same program as above but with a non-zero condition, so the "then"
    // push isn't skipped; the final Ret sees whatever's left after the Pop.
    let bytes: [UInt8] = [
        0x41, 0x01,  // 0-1: PushInt8 1 (truthy condition)
        0x55, 0x06,  // 2: JmpIfZ -> 2+6=8
        0x41, 0x63,  // 4: PushInt8 99
        0x65, 0x01,  // 6: Pop 1
        0x41, 0x02,  // 8: PushInt8 2
        0x01  // 10: Ret
    ]
    let executor = try makeExecutor(bytes: bytes)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(2)))
}

@Test func repeatWhileLoopActuallyExecutesTheCorrectIterationCount() throws {
    // local x = 0
    // repeat while x < 3
    //   x = x + 1
    // end repeat
    // return x
    let bytes: [UInt8] = [
        0x03,  // 0: PushZero
        0x52, 0x00,  // 1: SetLocal 0        (x = 0)
        0x4c, 0x00,  // 3: GetLocal 0        <- loop condition re-check target
        0x41, 0x03,  // 5: PushInt8 3
        0x0c,  // 7: Lt                (x < 3)
        0x55, 0x0b,  // 8: JmpIfZ -> 8+11=19
        0x4c, 0x00,  // 10: GetLocal 0
        0x41, 0x01,  // 12: PushInt8 1
        0x05,  // 14: Add
        0x52, 0x00,  // 15: SetLocal 0       (x = x + 1)
        0x54, 0x0e,  // 17: EndRepeat -> 17-14=3
        0x4c, 0x00,  // 19: GetLocal 0       <- after the loop
        0x01  // 21: Ret
    ]
    let executor = try makeExecutor(bytes: bytes, localCount: 1)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(3)))
}

@Test func invalidJumpTargetThrows() throws {
    let executor = try makeExecutor(bytes: [0x53, 0x63])  // Jmp to a position with no instruction
    #expect(throws: LingoVMError.self) {
        try executor.run()
    }
}
