import Foundation
import LingoBytecode
import LingoParser
import LingoRuntime
import LingoTranspiler
import Testing

@testable import LingoVM

/// Differential execution: the SAME Lingo program run two ways — transpiled
/// to Swift (the `Generated/` class, produced by `swiftlingoc` from
/// `Fixtures/differential.ls`) and interpreted by `LingoVM` from bytecode
/// assembled to mirror what Director's compiler emits for that source.
/// Every case asserts the two answers agree, so the transpiler's semantics
/// and the VM's semantics can't drift apart silently.
///
/// The repo has no source-to-bytecode compiler, so the bytecode side is
/// authored with `LingoAssembler` per handler; each mirror states the
/// source line it encodes.
@Suite("Differential Execution")
struct DifferentialTests {

    private func agree(_ transpiled: LingoValue, _ interpreted: LingoValue) -> Bool {
        LingoValue.equalsBool(lhs: transpiled, rhs: interpreted)
    }

    /// Runs one assembled handler through the VM.
    private func interpret(
        arguments: [String], locals: [String] = [], args: [LingoValue],
        receiver: LingoObject? = nil, environment: LingoEnvironment,
        _ build: (LingoAssembler) throws -> Void
    ) throws -> LingoValue {
        let assembler = LingoAssembler(arguments: arguments, locals: locals)
        try build(assembler)
        let (handler, names, literals) = try assembler.build()
        let chunk = ScriptChunk(
            scriptNumber: 1, literals: literals, handlers: [handler], propertyNameIDs: [],
            propertyDefaults: [:])
        return try LingoVM.call(
            handler: handler, chunk: chunk, names: names, args: args, receiver: receiver,
            environment: environment, version: 500)
    }

    /// The interpreted stand-in for the transpiled `Differential` instance:
    /// `on new` sets `total = 0`, so the property bag starts the same way.
    private func makeReceiver(_ environment: LingoEnvironment) -> HarnessObject {
        let receiver = HarnessObject(environment: environment)
        receiver.properties["total"] = .integer(0)
        return receiver
    }

    // MARK: - accumulate: property read-modify-write

    @Test func accumulateAgreesAndEvolvesTheSameState() throws {
        let environment = LingoEnvironment()
        let transpiled = Differential(environment: environment)
        let receiver = makeReceiver(environment)

        for n in [1, 5, -3, 100] {
            let swiftResult = transpiled.callMethod("accumulate", args: [.integer(n)])
            // on accumulate me, n
            //   total = total + n
            //   return total
            let vmResult = try interpret(
                arguments: ["me", "n"], args: [.object(receiver), .integer(n)],
                receiver: receiver, environment: environment
            ) { asm in
                asm.get("me")
                asm.get("me").getObjProp("total")
                asm.get("n").add()
                asm.setObjProp("total")
                asm.get("me").getObjProp("total").ret()
            }
            #expect(agree(swiftResult, vmResult), "accumulate(\(n))")
            #expect(
                agree(transpiled.getProperty("total"), receiver.getProperty("total")),
                "total after accumulate(\(n))")
        }
    }

    // MARK: - classify: comparison and branching

    @Test func classifyBranchesTheSameWay() throws {
        let environment = LingoEnvironment()
        let transpiled = Differential(environment: environment)

        for n in [-5, 0, 10, 11, 999] {
            let swiftResult = transpiled.callMethod("classify", args: [.integer(n)])
            // on classify me, n
            //   if n > 10 then return "big"
            //   else return "small"
            let vmResult = try interpret(
                arguments: ["me", "n"], args: [.void, .integer(n)], environment: environment
            ) { asm in
                asm.ifThenElse {
                    asm.get("n").pushInt(10).gt()
                } then: {
                    asm.pushString("big").ret()
                } else: {
                    asm.pushString("small").ret()
                }
                asm.ret()
            }
            #expect(agree(swiftResult, vmResult), "classify(\(n))")
        }
    }

    // MARK: - sumTo: the repeat-with lowering

    @Test func sumToLoopsToTheSameTotal() throws {
        let environment = LingoEnvironment()
        let transpiled = Differential(environment: environment)

        for n in [0, 1, 5, 10] {
            let swiftResult = transpiled.callMethod("sumTo", args: [.integer(n)])
            // on sumTo me, n
            //   s = 0
            //   repeat with i = 1 to n
            //     s = s + i
            //   end repeat
            //   return s
            let vmResult = try interpret(
                arguments: ["me", "n"], locals: ["s", "i"],
                args: [.void, .integer(n)], environment: environment
            ) { asm in
                asm.pushInt(0).set("s")
                asm.pushInt(1).set("i")
                asm.repeatWhile {
                    asm.get("i").get("n").ltEq()
                } body: {
                    asm.get("s").get("i").add().set("s")
                    asm.get("i").pushInt(1).add().set("i")
                }
                asm.get("s").ret()
            }
            #expect(agree(swiftResult, vmResult), "sumTo(\(n))")
        }
    }

    // MARK: - describe: string concatenation and a builtin call

    @Test func describeConcatenatesTheSame() throws {
        let environment = LingoEnvironment()
        let transpiled = Differential(environment: environment)

        for (who, score) in [("junkbot", 42), ("", 0), ("a b", -7)] {
            let swiftResult = transpiled.callMethod(
                "describe", args: [.string(who), .integer(score)])
            // on describe me, who, score
            //   return who && "scored" && string(score)
            let vmResult = try interpret(
                arguments: ["me", "who", "score"],
                args: [.void, .string(who), .integer(score)], environment: environment
            ) { asm in
                asm.get("who")
                asm.pushString("scored").joinPadStr()
                asm.get("score").pushArgList(1).extCall("string")
                asm.joinPadStr()
                asm.ret()
            }
            #expect(agree(swiftResult, vmResult), "describe(\(who), \(score))")
            #expect(swiftResult.asString() == "\(who) scored \(score)")
        }
    }

    // MARK: - firstOffset: builtins resolve identically on both paths

    @Test func builtinCallsAnswerTheSameOnBothPaths() throws {
        let environment = LingoEnvironment()
        let transpiled = Differential(environment: environment)

        for (needle, hay) in [("b", "abc"), ("z", "abc"), ("WÖR", "héllo wörld"), ("", "abc")] {
            let swiftResult = transpiled.callMethod(
                "firstOffset", args: [.string(needle), .string(hay)])
            // on firstOffset me, needle, hay
            //   return offset(needle, hay)
            let vmResult = try interpret(
                arguments: ["me", "needle", "hay"],
                args: [.void, .string(needle), .string(hay)], environment: environment
            ) { asm in
                asm.get("needle").get("hay").pushArgList(2).extCall("offset")
                asm.ret()
            }
            #expect(agree(swiftResult, vmResult), "offset(\(needle), \(hay))")
        }
    }
}

/// The committed `Generated/differential.swift` must be exactly what the
/// current transpiler produces from `Fixtures/differential.ls` — otherwise
/// the differential suite would be validating a stale artifact. Regenerate
/// with:
///
///     swift run swiftlingoc Tests/LingoDifferentialTests/Fixtures \
///         Tests/LingoDifferentialTests/Generated
@Suite("Generated Code Freshness")
struct GeneratedFreshnessTests {

    @Test func committedGeneratedCodeMatchesTheTranspiler() async throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixture = testsDirectory.appendingPathComponent("Fixtures/differential.ls")
        let generated = testsDirectory.appendingPathComponent("Generated/differential.swift")

        let source = try String(contentsOf: fixture, encoding: .utf8)
        var lexer = Lexer(input: source)
        let parser = Parser(tokens: lexer.tokenize())
        let script = parser.parseScript()
        #expect(parser.skippedTokens.isEmpty)

        let transpiler = LingoTranspiler(
            script: script, relativePath: "differential.ls",
            originalPath: "Fixtures/differential.ls")
        let fresh = await transpiler.transpile()
        let committed = try String(contentsOf: generated, encoding: .utf8)
        #expect(fresh == committed, "regenerate Generated/differential.swift with swiftlingoc")
    }
}
