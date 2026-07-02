import Testing
import LingoRuntime

@testable import LingoVM

@Test func newObjInstantiatesThroughHost() throws {
    let host = TestHost()
    let created = TestReceiver(environment: LingoEnvironment())
    // A host resolving any script name to the same pre-built instance is
    // enough to prove NewObj routes through `makeObject` rather than trying
    // to construct anything itself.
    let instantiatingHost = InstantiatingHost(objectToReturn: created)

    let executor = try makeExecutor(
        bytes: [
            0x43, 0x00,  // PushArgList 0
            0x73, 0x00,  // NewObj "MyScript"
            0x01  // Ret
        ],
        names: ["MyScript"], host: instantiatingHost)
    let result = try executor.run()

    guard case .object(let object) = result else {
        Issue.record("Expected an object result")
        return
    }
    #expect(object === created)
    _ = host
}

@Test func newObjWithNoHostReturnsVoid() throws {
    let executor = try makeExecutor(
        bytes: [0x43, 0x00, 0x73, 0x00, 0x01], names: ["MyScript"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
}

@Test func theBuiltinResolvesThroughHostMovie() throws {
    let host = TestHost()
    host.movieObject.properties["milliseconds"] = .integer(1234)

    let executor = try makeExecutor(
        bytes: [
            0x43, 0x00,  // PushArgList 0 (empty)
            0x66, 0x00,  // TheBuiltin "milliseconds"
            0x01  // Ret
        ],
        names: ["milliseconds"], host: host)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(1234)))
}

@Test func startTellAndEndTellAreStackNeutral() throws {
    // `tell window` ... `end tell` — StartTell just needs to consume its
    // window operand without disturbing anything else on the stack.
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x2a,  // PushInt8 42
            0x41, 0x01,  // PushInt8 1 (a stand-in "window")
            0x1c,  // StartTell
            0x1d,  // EndTell
            0x01  // Ret
        ])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(42)))
}

@Test func tellCallRedirectsToTheWindowResolvedByHost() throws {
    let environment = LingoEnvironment()
    let host = TestHost(environment: environment)
    let window = TestReceiver(environment: environment)
    host.windows[1] = window

    let executor = try makeExecutor(
        bytes: [
            0x41, 0x01,  // PushInt8 1 (window id)
            0x1c,  // StartTell
            0x43, 0x00,  // PushArgList 0
            0x63, 0x00,  // TellCall greet
            0x1d,  // EndTell
            0x01  // Ret
        ],
        names: ["greet"], host: host, environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("called:greet")))
    #expect(window.lastMethodCall?.name == "greet")
}

@Test func tellCallFallsBackToGlobalDispatchOutsideATellBlock() throws {
    let environment = LingoEnvironment()
    environment.registerGlobalFunction("someGlobalFn") { _ in .integer(77) }

    let executor = try makeExecutor(
        bytes: [
            0x43, 0x00,  // PushArgList 0
            0x63, 0x00,  // TellCall someGlobalFn
            0x01  // Ret
        ],
        names: ["someGlobalFn"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(77)))
}

@Test func tellCallFallsBackWhenWindowFailsToResolve() throws {
    let environment = LingoEnvironment()
    let host = TestHost(environment: environment)
    environment.registerGlobalFunction("someGlobalFn") { _ in .integer(55) }

    let executor = try makeExecutor(
        bytes: [
            0x41, 0x63,  // PushInt8 99 (unregistered window id)
            0x1c,  // StartTell
            0x43, 0x00,  // PushArgList 0
            0x63, 0x00,  // TellCall someGlobalFn
            0x1d,  // EndTell
            0x01  // Ret
        ],
        names: ["someGlobalFn"], host: host, environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(55)))
}

@Test func nestedTellBlocksRestoreTheOuterTargetAfterEndTell() throws {
    let environment = LingoEnvironment()
    let host = TestHost(environment: environment)
    let outerWindow = TestReceiver(environment: environment)
    let innerWindow = TestReceiver(environment: environment)
    host.windows[1] = outerWindow
    host.windows[2] = innerWindow

    let executor = try makeExecutor(
        bytes: [
            0x41, 0x01,  // PushInt8 1 (outer window id)
            0x1c,  // StartTell (outer)
            0x41, 0x02,  // PushInt8 2 (inner window id)
            0x1c,  // StartTell (inner)
            0x1d,  // EndTell (pop inner)
            0x43, 0x00,  // PushArgList 0
            0x63, 0x00,  // TellCall greet -- redirects to the outer target
            0x1d,  // EndTell (pop outer)
            0x01  // Ret
        ],
        names: ["greet"], host: host, environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("called:greet")))
    #expect(outerWindow.lastMethodCall?.name == "greet")
    #expect(innerWindow.lastMethodCall == nil)
}

@Test func callJavaScriptIsANoOp() throws {
    let executor = try makeExecutor(bytes: [0x41, 0x07, 0x26, 0x01])  // PushInt8 7, CallJavaScript, Ret
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(7)))
}

/// A host that always resolves `makeObject` to a fixed instance, regardless
/// of script name or arguments.
private final class InstantiatingHost: LingoVMHost {
    let movie: LingoObject = TestReceiver(environment: LingoEnvironment())
    let objectToReturn: LingoObject

    init(objectToReturn: LingoObject) {
        self.objectToReturn = objectToReturn
    }

    func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject? {
        objectToReturn
    }
}
