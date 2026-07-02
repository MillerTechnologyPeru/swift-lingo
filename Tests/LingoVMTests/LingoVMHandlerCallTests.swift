import Testing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

@Test func localCallInvokesAnotherHandlerInTheSameChunk() throws {
    // handler double(n) -- return n * 2
    let doubleHandler = try makeHandler(bytes: [
        0x4b, 0x00,  // GetParam (slot 0)
        0x41, 0x02,  // PushInt8 2
        0x04,  // Mul
        0x01  // Ret
    ])

    // handler main() -- return double(21)
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x15,  // PushInt8 21
            0x43, 0x01,  // PushArgList 1
            0x56, 0x00,  // LocalCall handlers[0] (double)
            0x01  // Ret
        ],
        handlers: [doubleHandler])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(42)))
}

@Test func localCallWithUnknownIndexThrows() throws {
    let executor = try makeExecutor(bytes: [0x43, 0x00, 0x56, 0x05, 0x01])  // PushArgList 0, LocalCall 5, Ret
    #expect(throws: LingoVMError.unknownLocalHandler(5)) {
        try executor.run()
    }
}

@Test func extCallDispatchesToRegisteredGlobalFunction() throws {
    LingoEnvironment.shared.registerGlobalFunction("vmTestExtCallTimesTen") { args in
        guard case .integer(let v) = args.first ?? .void else { return .void }
        return .integer(v * 10)
    }

    let executor = try makeExecutor(
        bytes: [
            0x41, 0x04,  // PushInt8 4
            0x43, 0x01,  // PushArgList 1
            0x57, 0x00,  // ExtCall vmTestExtCallTimesTen
            0x01  // Ret
        ],
        names: ["vmTestExtCallTimesTen"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(40)))
}

@Test func objCallGetAtIndexesAList() throws {
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x0a,  // PushInt8 10
            0x41, 0x14,  // PushInt8 20
            0x41, 0x1e,  // PushInt8 30
            0x43, 0x03,  // PushArgList 3
            0x1e,  // PushList
            0x41, 0x02,  // PushInt8 2
            0x43, 0x02,  // PushArgList 2 (list, index)
            0x67, 0x00,  // ObjCall getAt
            0x01  // Ret
        ],
        names: ["getAt"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(20)))
}

@Test func objCallSetAtMutatesTheUnderlyingList() throws {
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x0a,  // PushInt8 10
            0x41, 0x14,  // PushInt8 20
            0x43, 0x02,  // PushArgList 2
            0x1e,  // PushList
            0x64, 0x00,  // Peek 0 (keep the list on the stack for inspection after the call)
            0x41, 0x01,  // PushInt8 1
            0x41, 0x63,  // PushInt8 99
            0x43, 0x03,  // PushArgList 3 (list, index, value)
            0x67, 0x00,  // ObjCall setAt
            0x65, 0x01,  // Pop 1 (discard setAt's .void result)
            0x01  // Ret (returns the peeked list)
        ],
        names: ["setAt"])
    let result = try executor.run()

    let elements = result.asSequence()
    #expect(elements.count == 2)
    #expect(LingoValue.equalsBool(lhs: elements[0], rhs: .integer(99)))
    #expect(LingoValue.equalsBool(lhs: elements[1], rhs: .integer(20)))
}

@Test func objCallFallsBackToReceiverCallMethod() throws {
    let receiver = TestReceiver()
    LingoEnvironment.shared.setGlobal("vmTestObjCallReceiver", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestObjCallReceiver
            0x41, 0x05,  // PushInt8 5
            0x43, 0x02,  // PushArgList 2 (receiver, 5)
            0x67, 0x01,  // ObjCall greet
            0x01  // Ret
        ],
        names: ["vmTestObjCallReceiver", "greet"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("called:greet")))
    #expect(receiver.lastMethodCall?.name == "greet")
    #expect(receiver.lastMethodCall.map { LingoValue.equalsBool(lhs: $0.args[0], rhs: .integer(5)) } == true)
}

@Test func objCallV4DispatchesThroughGlobalFunctionValue() throws {
    LingoEnvironment.shared.registerGlobalFunction("vmTestObjCallV4Target") { _ in .integer(99) }
    LingoEnvironment.shared.setGlobal("vmTestObjCallV4Fn", .globalFunction("vmTestObjCallV4Target"))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestObjCallV4Fn
            0x43, 0x00,  // PushArgList 0
            0x58, 0x01,  // ObjCallV4 varType=1 (global/property passthrough)
            0x01  // Ret
        ],
        names: ["vmTestObjCallV4Fn"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(99)))
}
