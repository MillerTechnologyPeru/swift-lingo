import Testing
import BinaryParsing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

@Test func globalSetThenGetRoundTrips() throws {
    // Use a test-unique name so this doesn't collide with other tests
    // sharing `LingoEnvironment.shared`.
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x2a,  // PushInt8 42
            0x4f, 0x00,  // SetGlobal vmTestGlobalRoundTrip
            0x49, 0x00  // GetGlobal vmTestGlobalRoundTrip
        ],
        names: ["vmTestGlobalRoundTrip"])
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(42)))
}

@Test func localGetSetUsesSlotIndexNotName() throws {
    // multiplier is 8 in the test executor, so a raw operand of 8 addresses
    // local slot 1.
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x07,  // PushInt8 7
            0x52, 0x08,  // SetLocal (slot 1)
            0x4c, 0x08  // GetLocal (slot 1)
        ],
        localCount: 2)
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(7)))
    #expect(LingoValue.equalsBool(lhs: executor.locals[0], rhs: .void))
}

@Test func getParamReadsPositionally() throws {
    let executor = try makeExecutor(
        bytes: [0x4b, 0x08],  // GetParam (slot 1)
        args: [.integer(10), .integer(20)])
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(20)))
}

@Test func getParamOutOfRangeReturnsVoid() throws {
    let executor = try makeExecutor(bytes: [0x4b, 0x00], args: [])
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .void))
}

@Test func propGetSetDispatchesToReceiver() throws {
    let receiver = TestReceiver()
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x09,  // PushInt8 9
            0x50, 0x00,  // SetProp x
            0x4a, 0x00  // GetProp x
        ],
        names: ["x"], receiver: receiver)
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(9)))
    #expect(LingoValue.equalsBool(lhs: receiver.properties["x"] ?? .void, rhs: .integer(9)))
}

@Test func propGetWithNoReceiverReturnsVoid() throws {
    let executor = try makeExecutor(bytes: [0x4a, 0x00], names: ["x"], receiver: nil)
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .void))
}
