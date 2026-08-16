import LingoBytecode
import LingoRuntime
import Testing

@testable import LingoVM

/// List commands reach the VM as ordinary method calls whose receiver is a
/// list rather than an object, so they need their own dispatch step —
/// without it `(the actorList).add(me)` silently does nothing.
@Suite("Lingo VM List Dispatch")
struct ListDispatchTests {

    @Test func addMutatesTheReceivingList() {
        let list = LingoValue.list([.integer(1)])
        let result = LingoVMExecutor.dispatchListCall(
            method: "add", receiver: list, args: [.integer(2)])
        #expect(result != nil)
        guard case .listType(let raw) = list else { return }
        #expect(raw.elements.compactMap { $0.asInteger() } == [1, 2])
    }

    @Test func methodNamesAreCaseInsensitive() {
        let list = LingoValue.propertyList([])
        _ = LingoVMExecutor.dispatchListCall(
            method: "setAProp", receiver: list, args: [.symbol("k"), .integer(7)])
        #expect(list.listGetAProp(.symbol("k")).asInteger() == 7)
    }

    @Test func queriesReturnTheirValue() {
        let list = LingoValue.list([.integer(4), .integer(5)])
        let position = LingoVMExecutor.dispatchListCall(
            method: "getPos", receiver: list, args: [.integer(5)])
        #expect(position?.asInteger() == 2)
    }

    @Test func missingArgumentsBecomeVoidRatherThanTrapping() {
        let list = LingoValue.list([.integer(1)])
        let result = LingoVMExecutor.dispatchListCall(method: "add", receiver: list, args: [])
        #expect(result != nil)
        guard case .listType(let raw) = list else { return }
        #expect(raw.elements.count == 2)
    }

    /// Anything that isn't a list command, or isn't aimed at a list, has to
    /// fall through so ordinary object dispatch still runs.
    @Test func unrelatedCallsFallThrough() {
        #expect(
            LingoVMExecutor.dispatchListCall(
                method: "somethingElse", receiver: .list([]), args: []) == nil)
        #expect(
            LingoVMExecutor.dispatchListCall(
                method: "add", receiver: .integer(3), args: [.integer(1)]) == nil)
    }
}

/// `return expr` is compiled as a named call rather than an opcode: the
/// value arrives as the call's argument and the following `Ret` expects the
/// handler to have already finished. Treating it as an ordinary global
/// makes every `return expr` in a movie evaluate to VOID.
@Suite("Lingo VM Return")
struct ReturnCallTests {

    @Test func returnIsNotAnOrdinaryGlobal() {
        let environment = LingoEnvironment()
        // Nothing registers `return`, so a global dispatch answers VOID —
        // which is exactly why it needs handling inside the executor.
        if case .void = environment.callGlobal("return", args: [.integer(7)]) {
        } else {
            Issue.record("expected VOID from a global `return` dispatch")
        }
    }
}

/// `t.line.count` and `t.line[n]` compile to `objCall` `count`/`getProp`
/// with the STRING as receiver and the chunk type as a symbol — the
/// spelling `parseParams`-style config parsers are built from.
@Suite("Lingo VM String Chunk Collections")
struct StringChunkCollectionDispatchTests {

    private func run(
        _ build: (LingoAssembler) throws -> Void
    ) throws -> LingoValue {
        let assembler = LingoAssembler()
        try build(assembler)
        let (handler, names, literals) = try assembler.build()
        let chunk = ScriptChunk(
            scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
            propertyDefaults: [:])
        return try LingoVM.call(
            handler: handler, chunk: chunk, names: names, environment: LingoEnvironment(),
            version: 500)
    }

    @Test func countOfLinesOnAString() throws {
        // "a\rb\rc".line.count
        let result = try run { asm in
            asm.pushString("a\rb\rc").pushSymbol("line").pushArgList(2).objCall("count").ret()
        }
        #expect(result.asInteger() == 3)
    }

    @Test func indexingALineOnAString() throws {
        // "a\rb\rc".line[2]
        let result = try run { asm in
            asm.pushString("a\rb\rc").pushSymbol("line").pushInt(2)
            asm.pushArgList(3).objCall("getProp").ret()
        }
        #expect(result.asString() == "b")
    }

    @Test func rangedCharsOnAString() throws {
        // "[info]".char[2..5]
        let result = try run { asm in
            asm.pushString("[info]").pushSymbol("char").pushInt(2).pushInt(5)
            asm.pushArgList(4).objCall("getProp").ret()
        }
        #expect(result.asString() == "info")
    }

    @Test func lengthAsAPropertyOnAString() throws {
        // "hello".length — getObjProp on a string value.
        let result = try run { asm in
            asm.pushString("hello").getObjProp("length").ret()
        }
        #expect(result.asInteger() == 5)
    }

}
