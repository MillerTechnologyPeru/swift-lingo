import Testing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

@Test func repeatWhileLoopExecutesTheCorrectNumberOfIterations() throws {
    // local i = 0
    // local total = 0
    // repeat while i < 5
    //   total = total + i
    //   i = i + 1
    // end repeat
    // return total  -- 0 + 1 + 2 + 3 + 4 = 10
    let assembler = LingoAssembler(locals: ["i", "total"])
    assembler.pushInt(0).set("i")
    assembler.pushInt(0).set("total")

    let conditionLabel = assembler.makeLabel()
    let endLabel = assembler.makeLabel()

    assembler.mark(conditionLabel)
    assembler.get("i").pushInt(5).lt()
    assembler.jumpIfZero(to: endLabel)
    assembler.get("total").get("i").add().set("total")
    assembler.get("i").pushInt(1).add().set("i")
    assembler.endRepeat(to: conditionLabel)
    assembler.mark(endLabel)
    assembler.get("total").ret()

    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: LingoEnvironment(), version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(10)))
}

@Test func ifStatementInsideALoopComposesWithTheLoopsOwnJumps() throws {
    // local i = 0
    // local total = 0
    // repeat while i < 10
    //   if (i mod 2) = 0 then
    //     total = total + i
    //   end if
    //   i = i + 1
    // end repeat
    // return total  -- 0 + 2 + 4 + 6 + 8 = 20
    let assembler = LingoAssembler(locals: ["i", "total"])
    assembler.pushInt(0).set("i")
    assembler.pushInt(0).set("total")

    let conditionLabel = assembler.makeLabel()
    let endLoopLabel = assembler.makeLabel()
    let skipIfLabel = assembler.makeLabel()

    assembler.mark(conditionLabel)
    assembler.get("i").pushInt(10).lt()
    assembler.jumpIfZero(to: endLoopLabel)

    assembler.get("i").pushInt(2).mod().pushInt(0).eq()
    assembler.jumpIfZero(to: skipIfLabel)
    assembler.get("total").get("i").add().set("total")
    assembler.mark(skipIfLabel)

    assembler.get("i").pushInt(1).add().set("i")
    assembler.endRepeat(to: conditionLabel)
    assembler.mark(endLoopLabel)
    assembler.get("total").ret()

    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: LingoEnvironment(), version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(20)))
}

@Test func unresolvedLabelThrows() throws {
    let assembler = LingoAssembler()
    let label = assembler.makeLabel()
    assembler.jump(to: label)
    assembler.ret()

    #expect(throws: LingoAssemblerError.unresolvedLabel) {
        try assembler.build()
    }
}
