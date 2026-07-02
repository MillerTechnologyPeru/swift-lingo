import Testing
import BinaryParsing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

@Test func arithmeticFollowsOperatorPrecedenceAsCompiled() throws {
    // 1 + (2 * 3), compiled with the multiply already evaluated: push 1, push 2, push 3, mul, add
    let executor = try makeExecutor(bytes: [0x41, 0x01, 0x41, 0x02, 0x41, 0x03, 0x04, 0x05])
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(7)))
}

@Test func divisionByZeroProducesVoidNotError() throws {
    let executor = try makeExecutor(bytes: [0x41, 0x05, 0x03, 0x07])  // PushInt8 5, PushZero, Div
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .void))
}

@Test func comparisonPushesIntegerBoolean() throws {
    let executor = try makeExecutor(bytes: [0x41, 0x02, 0x41, 0x05, 0x0c])  // PushInt8 2, PushInt8 5, Lt
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(1)))
}

@Test func notInvertsTruthiness() throws {
    let executor = try makeExecutor(bytes: [0x03, 0x14])  // PushZero, Not
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(1)))
}

@Test func peekDuplicatesWithoutConsuming() throws {
    // PushInt8 1, PushInt8 2, Peek 0 (duplicate top) -> stack: [1, 2, 2]
    let executor = try makeExecutor(bytes: [0x41, 0x01, 0x41, 0x02, 0x64, 0x00])
    _ = try executor.run()

    #expect(executor.stack.count == 3)
    #expect(LingoValue.equalsBool(lhs: executor.stack[2], rhs: .integer(2)))
}

@Test func popDiscardsRequestedCount() throws {
    // PushInt8 1, PushInt8 2, PushInt8 3, Pop 2 -> stack: [1]
    let executor = try makeExecutor(bytes: [0x41, 0x01, 0x41, 0x02, 0x41, 0x03, 0x65, 0x02])
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(1)))
}

@Test func swapExchangesTopTwoValues() throws {
    // PushInt8 1, PushInt8 2, Swap -> stack: [2, 1]
    let executor = try makeExecutor(bytes: [0x41, 0x01, 0x41, 0x02, 0x21])
    _ = try executor.run()

    #expect(executor.stack.count == 2)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .integer(2)))
    #expect(LingoValue.equalsBool(lhs: executor.stack[1], rhs: .integer(1)))
}

@Test func pushConsResolvesLiteralPool() throws {
    let executor = try makeExecutor(bytes: [0x44, 0x00], literals: [.string("hello")])  // PushCons 0
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    #expect(LingoValue.equalsBool(lhs: executor.stack[0], rhs: .string("hello")))
}

@Test func pushArgListBuildsListInPushOrder() throws {
    // PushInt8 1, PushInt8 2, PushInt8 3, PushArgList 3
    let executor = try makeExecutor(bytes: [0x41, 0x01, 0x41, 0x02, 0x41, 0x03, 0x43, 0x03])
    _ = try executor.run()

    #expect(executor.stack.count == 1)
    let elements = executor.stack[0].asSequence()
    #expect(elements.count == 3)
    #expect(LingoValue.equalsBool(lhs: elements[0], rhs: .integer(1)))
    #expect(LingoValue.equalsBool(lhs: elements[1], rhs: .integer(2)))
    #expect(LingoValue.equalsBool(lhs: elements[2], rhs: .integer(3)))
}
