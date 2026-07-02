import Testing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

/// Builds a `handler`'s assembled bytecode into a minimal `ScriptChunk` and
/// runs it through `LingoVM.call`, so each fixture only needs to state its
/// assembler calls and expected result.
private func run(
    arguments: [String] = [], locals: [String] = [],
    environment: LingoEnvironment = LingoEnvironment(),
    _ build: (LingoAssembler) throws -> Void
) throws -> LingoValue {
    let assembler = LingoAssembler(arguments: arguments, locals: locals)
    try build(assembler)
    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    return try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: environment, version: 500)
}

@Test func pushIntPicksTheSmallestFittingTierAndArithmeticWorks() throws {
    // return (2 + 3) * 4
    let result = try run { asm in
        asm.pushInt(2).pushInt(3).add()
        asm.pushInt(4).mul()
        asm.ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(20)))
}

@Test func pushIntHandlesValuesOutsideInt16ViaTheLiteralPool() throws {
    // return 100000 + 1  (100000 doesn't fit Int16, routes through PushCons)
    let result = try run { asm in
        asm.pushInt(100_000).pushInt(1).add().ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(100_001)))
}

@Test func pushFloatAndPushStringUseTheLiteralPool() throws {
    let result = try run { asm in
        asm.pushFloat(3.5).ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .float(3.5)))

    let stringResult = try run { asm in
        asm.pushString("hello").ret()
    }
    #expect(LingoValue.equalsBool(lhs: stringResult, rhs: .string("hello")))
}

@Test func pushSymbolProducesASymbolValue() throws {
    let result = try run { asm in
        asm.pushSymbol("done").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .symbol("done")))
}

@Test func globalVariableGetSetRoundTrips() throws {
    let result = try run { asm in
        asm.pushInt(7).set("counter")
        asm.get("counter").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(7)))
}

@Test func localVariableGetSetRoundTrips() throws {
    let result = try run(locals: ["total"]) { asm in
        asm.pushInt(42).set("total")
        asm.get("total").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(42)))
}

@Test func paramVariableIsReadable() throws {
    let assembler = LingoAssembler(arguments: ["n"])
    assembler.get("n").ret()
    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, args: [.integer(9)],
        environment: LingoEnvironment(), version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(9)))
}

@Test func comparisonAndLogicOpcodesWork() throws {
    let result = try run { asm in
        asm.pushInt(3).pushInt(5).lt().ret()  // 3 < 5
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(1)))
}

@Test func popAndPeekAdjustTheStack() throws {
    let result = try run { asm in
        asm.pushInt(1).pushInt(2).pushInt(3)
        asm.pop(2)  // discard 2 and 3
        asm.ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(1)))

    let peeked = try run { asm in
        asm.pushInt(11)
        asm.peek(0)  // duplicate the top without consuming it
        asm.add()  // 11 + 11
        asm.ret()
    }
    #expect(LingoValue.equalsBool(lhs: peeked, rhs: .integer(22)))
}
