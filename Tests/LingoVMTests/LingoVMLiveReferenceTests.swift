import Testing
import LingoRuntime

@testable import LingoVM

@Test func pushChunkVarRefProducesALiveReferenceThatReadsAGlobal() throws {
    // global x = 5
    // return x.value  -- read through a PushChunkVarRef-built reference
    let environment = LingoEnvironment()
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x05,  // PushInt8 5
            0x4f, 0x00,  // SetGlobal x
            0x46, 0x00,  // PushVarRef x
            0x6d, 0x01,  // PushChunkVarRef varType=1 (global) -> live reference object
            0x61, 0x01,  // GetObjProp value
            0x01  // Ret
        ],
        names: ["x", "value"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(5)))
}

@Test func pushChunkVarRefProducesALiveReferenceThatWritesAGlobal() throws {
    // global x = 5
    // x.value = 99  -- write through a PushChunkVarRef-built reference
    // return x
    let environment = LingoEnvironment()
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x05,  // PushInt8 5
            0x4f, 0x00,  // SetGlobal x
            0x46, 0x00,  // PushVarRef x
            0x6d, 0x01,  // PushChunkVarRef varType=1 (global) -> live reference object
            0x41, 0x63,  // PushInt8 99
            0x62, 0x01,  // SetObjProp value
            0x49, 0x00,  // GetGlobal x
            0x01  // Ret
        ],
        names: ["x", "value"], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(99)))
    #expect(LingoValue.equalsBool(lhs: environment.getGlobal("x"), rhs: .integer(99)))
}

@Test func objCallSetContentsAfterAppendsToAReferencedGlobal() throws {
    // global x = "one two"
    // x.setContentsAfter(" three")
    // return x
    let environment = LingoEnvironment()
    let executor = try makeExecutor(
        bytes: [
            0x44, 0x00,  // PushCons 0 ("one two")
            0x4f, 0x00,  // SetGlobal x
            0x46, 0x00,  // PushVarRef x
            0x6d, 0x01,  // PushChunkVarRef varType=1 (global) -> live reference object
            0x44, 0x08,  // PushCons 1 (" three")
            0x43, 0x02,  // PushArgList 2 (reference, " three")
            0x67, 0x01,  // ObjCall setContentsAfter
            0x49, 0x00,  // GetGlobal x
            0x01  // Ret
        ],
        names: ["x", "setContentsAfter"], literals: [.string("one two"), .string(" three")],
        environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("one two three")))
}

@Test func objCallDeleteClearsAReferencedGlobal() throws {
    // global x = "hello"
    // x.delete()
    // return x
    let environment = LingoEnvironment()
    let executor = try makeExecutor(
        bytes: [
            0x44, 0x00,  // PushCons 0 ("hello")
            0x4f, 0x00,  // SetGlobal x
            0x46, 0x00,  // PushVarRef x
            0x6d, 0x01,  // PushChunkVarRef varType=1 (global) -> live reference object
            0x43, 0x01,  // PushArgList 1 (reference)
            0x67, 0x01,  // ObjCall delete
            0x49, 0x00,  // GetGlobal x
            0x01  // Ret
        ],
        names: ["x", "delete"], literals: [.string("hello")], environment: environment)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("")))
}
