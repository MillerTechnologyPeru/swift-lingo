import Testing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

@Test func localCallInvokesAnotherAssembledHandlerInTheSameChunk() throws {
    // handler double(n) -- return n * 2
    // handler main() -- return double(21)
    let doubleAssembler = LingoAssembler(arguments: ["n"])
    doubleAssembler.get("n").pushInt(2).mul().ret()
    let (doubleHandler, namesAfterDouble, literalsAfterDouble) = try doubleAssembler.build()

    let mainAssembler = LingoAssembler(names: namesAfterDouble, literals: literalsAfterDouble)
    mainAssembler.pushInt(21).pushArgList(1).localCall(0).ret()
    let (mainHandler, names, literals) = try mainAssembler.build()

    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [doubleHandler, mainHandler],
        propertyNameIDs: [], propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: mainHandler, chunk: chunk, names: names, environment: LingoEnvironment(), version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(42)))
}

@Test func extCallDispatchesToARegisteredGlobalFunction() throws {
    let environment = LingoEnvironment()
    environment.registerGlobalFunction("timesTen") { args in
        guard case .integer(let value) = args.first ?? .void else { return .void }
        return .integer(value * 10)
    }

    let assembler = LingoAssembler()
    assembler.pushInt(4).pushArgList(1).extCall("timesTen").ret()
    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: environment, version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(40)))
}

@Test func getObjPropAndSetObjPropRoundTripThroughAHarnessObject() throws {
    // global receiver
    // receiver.name = "Neo"
    // return receiver.name
    let environment = LingoEnvironment()
    let receiver = HarnessObject(environment: environment)
    environment.setGlobal("receiver", .object(receiver))

    let assembler = LingoAssembler()
    assembler.get("receiver").pushString("Neo").setObjProp("name")
    assembler.get("receiver").getObjProp("name")
    assembler.ret()
    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: environment, version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("Neo")))
    #expect(LingoValue.equalsBool(lhs: receiver.properties["name"] ?? .void, rhs: .string("Neo")))
}

@Test func objCallDispatchesThroughAHarnessObjectsRegisteredMethod() throws {
    // global receiver
    // return receiver.greet(5)
    let environment = LingoEnvironment()
    let receiver = HarnessObject(environment: environment)
    receiver.methods["greet"] = { args in
        guard case .integer(let n) = args.first ?? .void else { return .void }
        return .string("hello:\(n)")
    }
    environment.setGlobal("receiver", .object(receiver))

    let assembler = LingoAssembler()
    assembler.get("receiver").pushInt(5).pushArgList(2).objCall("greet").ret()
    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, environment: environment, version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("hello:5")))
    #expect(receiver.lastMethodCall?.name == "greet")
}

@Test func hostBackedLoopSumsAPropertyAcrossSeveralSprites() throws {
    // A loop that reads a `size` property off sprites 1...3 (resolved
    // through `HarnessHost`, via an `extCall` bridge closing over the host —
    // the assembler has no dedicated "resolve sprite N" opcode helper of its
    // own; that's the V4 `Get`/`Set` numbered-property family, out of scope
    // for this pass) and sums them — combines control flow, the host, and
    // harness objects in one integrated scenario.
    let environment = LingoEnvironment()
    let host = HarnessHost(environment: environment)
    for index in 1...3 {
        let sprite = HarnessObject(environment: environment)
        sprite.properties["size"] = .integer(index * 10)
        host.sprites[index] = sprite
    }
    environment.registerGlobalFunction("spriteSize") { args in
        guard case .integer(let channel) = args.first ?? .void, let sprite = host.sprites[channel]
        else { return .void }
        return sprite.getProperty("size")
    }

    let assembler = LingoAssembler(locals: ["i", "total"])
    assembler.pushInt(0).set("total")
    assembler.pushInt(1).set("i")

    let conditionLabel = assembler.makeLabel()
    let endLabel = assembler.makeLabel()

    assembler.mark(conditionLabel)
    assembler.get("i").pushInt(4).lt()
    assembler.jumpIfZero(to: endLabel)
    assembler.get("total")
    assembler.get("i").pushArgList(1).extCall("spriteSize")
    assembler.add().set("total")
    assembler.get("i").pushInt(1).add().set("i")
    assembler.endRepeat(to: conditionLabel)
    assembler.mark(endLabel)
    assembler.get("total").ret()

    let (handler, names, literals) = try assembler.build()
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    let result = try LingoVM.call(
        handler: handler, chunk: chunk, names: names, host: host, environment: environment, version: 500)

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(60)))
}
