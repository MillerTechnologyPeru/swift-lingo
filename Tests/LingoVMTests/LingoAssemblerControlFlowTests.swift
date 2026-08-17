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

/// `repeat with x in list` keeps the list, its count and the counter on the
/// stack and reaches them by `Peek` depth. A call made as a statement in the
/// body (`PushArgListNoRet`) must leave nothing behind, or `add 1` bumps the
/// stray result instead of the counter and the loop never ends — which is
/// exactly what froze the junkbot sample's `setPlayfield` on its
/// `me.placePiece(part)` loop.
@Test func statementCallsInsideRepeatWithInLeaveTheStackAlone() throws {
    let environment = LingoEnvironment()
    environment.setGlobal("items", .list([.integer(1), .integer(2), .integer(3)]))
    var seen: [Int] = []
    environment.registerGlobalFunction("note") { args in
        seen.append(args.first?.asInteger() ?? -1)
        return .integer(999)  // a result nobody asked for
    }

    // The compiler's lowering of `repeat with p in items / note(p) / end repeat`:
    //   items; count(items); 1
    //   loop: peek 0 (i); peek 2 (count); ltEq; jmpIfZ end
    //         peek 2 (list); peek 1 (i); getAt; setLocal p
    //         getLocal p; pushArgListNoRet 1; extCall note
    //         pushInt 1; add; endRepeat loop
    //   end: pop 3
    let assembler = LingoAssembler(locals: ["p"])
    assembler.get("items")
    assembler.peek(0).pushArgList(1).extCall("count")
    assembler.pushInt(1)
    let loop = assembler.makeLabel()
    let end = assembler.makeLabel()
    assembler.mark(loop)
    assembler.peek(0).peek(2).ltEq()
    assembler.jumpIfZero(to: end)
    assembler.peek(2).peek(1).pushArgList(2).extCall("getAt").set("p")
    assembler.get("p").pushArgListNoRet(1).extCall("note")
    assembler.pushInt(1).add()
    assembler.endRepeat(to: loop)
    assembler.mark(end)
    assembler.pop(3)
    assembler.ret()

    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: environment, version: 500)

    #expect(seen == [1, 2, 3])
    // Nothing left over: a bare `ret` answers VOID, not the last call's result.
    if case .void = result {} else { Issue.record("expected VOID, got \(result)") }
}
