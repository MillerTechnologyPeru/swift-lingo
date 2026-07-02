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
    let environment = LingoEnvironment()
    environment.registerGlobalFunction("vmTestExtCallTimesTen") { args in
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
        names: ["vmTestExtCallTimesTen"], environment: environment)
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

@Test func objCallGetPropIndexesAnObjectsListProperty() throws {
    let environment = LingoEnvironment()
    let receiver = TestReceiver(environment: environment)
    receiver.properties["items"] = .list([.integer(10), .integer(20), .integer(30)])
    environment.setGlobal("vmTestGetPropReceiver", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestGetPropReceiver
            0x45, 0x01,  // PushSymb items
            0x41, 0x02,  // PushInt8 2
            0x43, 0x03,  // PushArgList 3 (receiver, #items, 2)
            0x67, 0x02,  // ObjCall getProp
            0x01  // Ret
        ],
        names: ["vmTestGetPropReceiver", "items", "getProp"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(20)))
}

@Test func objCallGetPropRefReadsARangeOfAnObjectsStringProperty() throws {
    let environment = LingoEnvironment()
    let receiver = TestReceiver(environment: environment)
    receiver.properties["name"] = .string("hello world")
    environment.setGlobal("vmTestGetPropRefReceiver", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestGetPropRefReceiver
            0x45, 0x01,  // PushSymb name
            0x41, 0x01,  // PushInt8 1
            0x41, 0x05,  // PushInt8 5
            0x43, 0x04,  // PushArgList 4 (receiver, #name, 1, 5)
            0x67, 0x02,  // ObjCall getPropRef
            0x01  // Ret
        ],
        names: ["vmTestGetPropRefReceiver", "name", "getPropRef"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("hello")))
}

@Test func objCallSetPropMutatesAnObjectsListProperty() throws {
    let environment = LingoEnvironment()
    let receiver = TestReceiver(environment: environment)
    receiver.properties["items"] = .list([.integer(10), .integer(20)])
    environment.setGlobal("vmTestSetPropReceiver", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestSetPropReceiver
            0x45, 0x01,  // PushSymb items
            0x41, 0x01,  // PushInt8 1
            0x41, 0x63,  // PushInt8 99
            0x43, 0x04,  // PushArgList 4 (receiver, #items, 1, 99)
            0x67, 0x02,  // ObjCall setProp
            0x01  // Ret
        ],
        names: ["vmTestSetPropReceiver", "items", "setProp"], environment: environment)
    _ = try executor.run()

    let elements = receiver.properties["items"]?.asSequence() ?? []
    #expect(elements.count == 2)
    #expect(LingoValue.equalsBool(lhs: elements[0], rhs: .integer(99)))
    #expect(LingoValue.equalsBool(lhs: elements[1], rhs: .integer(20)))
}

@Test func objCallSetPropWithRangeReplacesASpanOfAStringProperty() throws {
    let environment = LingoEnvironment()
    let receiver = TestReceiver(environment: environment)
    receiver.properties["name"] = .string("hello world")
    environment.setGlobal("vmTestSetPropRangeReceiver", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestSetPropRangeReceiver
            0x45, 0x01,  // PushSymb name
            0x41, 0x01,  // PushInt8 1
            0x41, 0x05,  // PushInt8 5
            0x44, 0x00,  // PushCons 0 ("HELLO")
            0x43, 0x05,  // PushArgList 5 (receiver, #name, 1, 5, "HELLO")
            0x67, 0x02,  // ObjCall setProp
            0x01  // Ret
        ],
        names: ["vmTestSetPropRangeReceiver", "name", "setProp"], literals: [.string("HELLO")],
        environment: environment)
    _ = try executor.run()

    #expect(LingoValue.equalsBool(lhs: receiver.properties["name"] ?? .void, rhs: .string("HELLO world")))
}

@Test func objCallDeferredMethodsAreNoOpsAndDoNotMisdispatch() throws {
    // `hilite`/`delete`/`setContents*` take a chunk/variable reference as
    // their first argument, not a receiver — even when that argument
    // happens to be an object, it must not be misinterpreted as "call a
    // method literally named `hilite` on this receiver."
    let environment = LingoEnvironment()
    let receiver = TestReceiver(environment: environment)
    environment.setGlobal("vmTestHiliteTarget", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestHiliteTarget
            0x42, 0x01,  // PushArgListNoRet 1
            0x67, 0x01,  // ObjCall hilite
            0x01  // Ret
        ],
        names: ["vmTestHiliteTarget", "hilite"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
    #expect(receiver.lastMethodCall == nil)
}

@Test func objCallFallsBackToReceiverCallMethod() throws {
    let environment = LingoEnvironment()
    let receiver = TestReceiver(environment: environment)
    environment.setGlobal("vmTestObjCallReceiver", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestObjCallReceiver
            0x41, 0x05,  // PushInt8 5
            0x43, 0x02,  // PushArgList 2 (receiver, 5)
            0x67, 0x01,  // ObjCall greet
            0x01  // Ret
        ],
        names: ["vmTestObjCallReceiver", "greet"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("called:greet")))
    #expect(receiver.lastMethodCall?.name == "greet")
    #expect(receiver.lastMethodCall.map { LingoValue.equalsBool(lhs: $0.args[0], rhs: .integer(5)) } == true)
}

@Test func objCallV4DispatchesThroughGlobalFunctionValue() throws {
    let environment = LingoEnvironment()
    environment.registerGlobalFunction("vmTestObjCallV4Target") { _ in .integer(99) }
    environment.setGlobal("vmTestObjCallV4Fn", .globalFunction(environment, "vmTestObjCallV4Target"))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestObjCallV4Fn
            0x43, 0x00,  // PushArgList 0
            0x58, 0x01,  // ObjCallV4 varType=1 (global/property passthrough)
            0x01  // Ret
        ],
        names: ["vmTestObjCallV4Fn"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(99)))
}
