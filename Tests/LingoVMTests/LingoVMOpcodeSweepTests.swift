import Testing
import LingoRuntime

@testable import LingoVM

@Test func newObjInstantiatesThroughHost() throws {
    let host = TestHost()
    let created = TestReceiver()
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

@Test func callJavaScriptIsANoOp() throws {
    let executor = try makeExecutor(bytes: [0x41, 0x07, 0x26, 0x01])  // PushInt8 7, CallJavaScript, Ret
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(7)))
}

/// A host that always resolves `makeObject` to a fixed instance, regardless
/// of script name or arguments.
private final class InstantiatingHost: LingoVMHost {
    let movie: LingoObject = TestReceiver()
    let objectToReturn: LingoObject

    init(objectToReturn: LingoObject) {
        self.objectToReturn = objectToReturn
    }

    func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject? {
        objectToReturn
    }
}
