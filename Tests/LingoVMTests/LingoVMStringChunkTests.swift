import Testing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

@Test func joinStrConcatenatesStrings() throws {
    let executor = try makeExecutor(
        bytes: [0x44, 0x00, 0x44, 0x08, 0x0a, 0x01],  // PushCons 0, PushCons 1, JoinStr, Ret
        literals: [.string("Hello"), .string(" World")])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("Hello World")))
}

@Test func containsStrFindsSubstring() throws {
    let executor = try makeExecutor(
        bytes: [0x44, 0x00, 0x44, 0x08, 0x15, 0x01],  // PushCons 0, PushCons 1, ContainsStr, Ret
        literals: [.string("Hello World"), .string("World")])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(1)))
}

@Test func getChunkExtractsTheSpecifiedWord() throws {
    // "one two three", word 2 -> "two". `GetChunk` pops the string *first*
    // (from the top), then the chunk-range values, so the string must be
    // pushed *last* — the opposite order from `PutChunk`/`DeleteChunk`,
    // which resolve their variable before the chunk range.
    let executor = try makeExecutor(
        bytes: [
            0x03, 0x03,  // firstChar=0, lastChar=0
            0x41, 0x02, 0x41, 0x02,  // firstWord=2, lastWord=2
            0x03, 0x03,  // firstItem=0, lastItem=0
            0x03, 0x03,  // firstLine=0, lastLine=0
            0x44, 0x00,  // PushCons "one two three"
            0x17,  // GetChunk
            0x01  // Ret
        ],
        literals: [.string("one two three")])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("two")))
}

@Test func putIntoGlobalWritesBackByName() throws {
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x05,  // PushInt8 5   (value, pushed first)
            0x46, 0x00,  // PushVarRef vmTestPutGlobal
            0x59, 0x11,  // Put into(1)<<4 | global(1)
            0x49, 0x00,  // GetGlobal vmTestPutGlobal
            0x01  // Ret
        ],
        names: ["vmTestPutGlobal"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(5)))
}

@Test func putChunkReplacesAWordInPlace() throws {
    LingoEnvironment.shared.setGlobal("vmTestPutChunkGlobal", .string("one two three"))

    let executor = try makeExecutor(
        bytes: [
            0x44, 0x00,  // PushCons "TWO"    (value)
            0x03, 0x03,  // firstChar=0, lastChar=0
            0x41, 0x02, 0x41, 0x02,  // firstWord=2, lastWord=2
            0x03, 0x03,  // firstItem=0, lastItem=0
            0x03, 0x03,  // firstLine=0, lastLine=0
            0x46, 0x00,  // PushVarRef vmTestPutChunkGlobal
            0x5a, 0x11,  // PutChunk into(1)<<4 | global(1)
            0x49, 0x00,  // GetGlobal vmTestPutChunkGlobal
            0x01  // Ret
        ],
        names: ["vmTestPutChunkGlobal"], literals: [.string("TWO")])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("one TWO three")))
}

@Test func deleteChunkClearsTheSpecifiedWord() throws {
    LingoEnvironment.shared.setGlobal("vmTestDeleteChunkGlobal", .string("one two three"))

    let executor = try makeExecutor(
        bytes: [
            0x03, 0x03,  // firstChar=0, lastChar=0
            0x41, 0x02, 0x41, 0x02,  // firstWord=2, lastWord=2
            0x03, 0x03,  // firstItem=0, lastItem=0
            0x03, 0x03,  // firstLine=0, lastLine=0
            0x46, 0x00,  // PushVarRef vmTestDeleteChunkGlobal
            0x5b, 0x01,  // DeleteChunk varType=1 (global)
            0x49, 0x00,  // GetGlobal vmTestDeleteChunkGlobal
            0x01  // Ret
        ],
        names: ["vmTestDeleteChunkGlobal"])
    let result = try executor.run()

    // settingChunk replaces the word with "", leaving the space separators
    // either side — matches what LingoRuntime's own chunk-join actually
    // produces, not an idealized "clean delete".
    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("one  three")))
}

@Test func spriteCollisionOpcodesDelegateToHost() throws {
    let host = TestHost()
    let spriteA = TestReceiver()
    let spriteB = TestReceiver()
    LingoEnvironment.shared.setGlobal("vmTestSpriteA", .object(spriteA))
    LingoEnvironment.shared.setGlobal("vmTestSpriteB", .object(spriteB))

    func runOntoSpr() throws -> LingoValue {
        try makeExecutor(
            bytes: [
                0x49, 0x00,  // GetGlobal vmTestSpriteA
                0x49, 0x01,  // GetGlobal vmTestSpriteB
                0x19,  // OntoSpr
                0x01  // Ret
            ],
            names: ["vmTestSpriteA", "vmTestSpriteB"], host: host
        ).run()
    }

    host.intersects = false
    #expect(LingoValue.equalsBool(lhs: try runOntoSpr(), rhs: .integer(0)))

    host.intersects = true
    #expect(LingoValue.equalsBool(lhs: try runOntoSpr(), rhs: .integer(1)))
}

@Test func spriteCollisionWithNonObjectOperandsIsFalse() throws {
    let host = TestHost()
    host.intersects = true  // even with a "yes" host, non-objects can't collide

    let executor = try makeExecutor(
        bytes: [
            0x41, 0x01,  // PushInt8 1 (not an object)
            0x41, 0x02,  // PushInt8 2 (not an object)
            0x19,  // OntoSpr
            0x01  // Ret
        ],
        host: host)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(0)))
}
