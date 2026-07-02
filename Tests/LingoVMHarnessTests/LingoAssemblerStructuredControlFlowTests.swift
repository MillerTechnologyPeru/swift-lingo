import Testing
import LingoBytecode
import LingoRuntime
import LingoVM

@testable import LingoVMHarness

private func run(
    arguments: [String] = [], locals: [String] = [],
    environment: LingoEnvironment = LingoEnvironment(),
    _ build: (LingoAssembler) -> Void
) throws -> LingoValue {
    let assembler = LingoAssembler(arguments: arguments, locals: locals)
    build(assembler)
    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    return try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: environment, version: 500)
}

@Test func ifThenSkipsTheBodyWhenConditionIsFalse() throws {
    let result = try run(locals: ["x"]) { asm in
        asm.pushInt(0).set("x")
        asm.ifThen(
            condition: { asm.pushInt(0) },
            then: { asm.pushInt(99).set("x") })
        asm.get("x").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(0)))
}

@Test func ifThenRunsTheBodyWhenConditionIsTrue() throws {
    let result = try run(locals: ["x"]) { asm in
        asm.pushInt(0).set("x")
        asm.ifThen(
            condition: { asm.pushInt(1) },
            then: { asm.pushInt(99).set("x") })
        asm.get("x").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(99)))
}

@Test func ifThenElseTakesTheElseBranchWhenConditionIsFalse() throws {
    let result = try run { asm in
        asm.ifThenElse(
            condition: { asm.pushInt(0) },
            then: { asm.pushString("then") },
            else: { asm.pushString("else") })
        asm.ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("else")))
}

@Test func ifThenElseTakesTheThenBranchWhenConditionIsTrue() throws {
    let result = try run { asm in
        asm.ifThenElse(
            condition: { asm.pushInt(1) },
            then: { asm.pushString("then") },
            else: { asm.pushString("else") })
        asm.ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("then")))
}

@Test func repeatWhileHelperMatchesTheHandAssembledLoop() throws {
    // local i = 0; local total = 0
    // repeat while i < 5 -- total = total + i; i = i + 1 -- end repeat
    // return total  -- 0 + 1 + 2 + 3 + 4 = 10
    let result = try run(locals: ["i", "total"]) { asm in
        asm.pushInt(0).set("i")
        asm.pushInt(0).set("total")
        asm.repeatWhile(
            condition: { asm.get("i").pushInt(5).lt() },
            body: {
                asm.get("total").get("i").add().set("total")
                asm.get("i").pushInt(1).add().set("i")
            })
        asm.get("total").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(10)))
}

@Test func nestedIfThenInsideRepeatWhileComposesCorrectly() throws {
    // Same "sum the even numbers 0..<10" scenario as the hand-assembled
    // control-flow test, built with the structured helpers instead.
    let result = try run(locals: ["i", "total"]) { asm in
        asm.pushInt(0).set("i")
        asm.pushInt(0).set("total")
        asm.repeatWhile(
            condition: { asm.get("i").pushInt(10).lt() },
            body: {
                asm.ifThen(
                    condition: { asm.get("i").pushInt(2).mod().pushInt(0).eq() },
                    then: { asm.get("total").get("i").add().set("total") })
                asm.get("i").pushInt(1).add().set("i")
            })
        asm.get("total").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(20)))
}

@Test func repeatWithCounterIteratesInclusiveOfTheEndValue() throws {
    // repeat with i = 1 to 5 -- total = total + i -- end repeat
    // return total  -- 1 + 2 + 3 + 4 + 5 = 15
    let result = try run(locals: ["i", "total"]) { asm in
        asm.pushInt(0).set("total")
        asm.repeatWithCounter("i", from: 1, to: 5) {
            asm.get("total").get("i").add().set("total")
        }
        asm.get("total").ret()
    }
    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(15)))
}
