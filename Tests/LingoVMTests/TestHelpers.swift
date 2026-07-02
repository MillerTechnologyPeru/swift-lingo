import BinaryParsing
import LingoBytecode
import LingoRuntime

@testable import LingoVM

/// Builds a standalone `HandlerDef` from hand-encoded bytecode, for tests
/// that need a *second* handler (e.g. to exercise `LocalCall`) alongside the
/// one `makeExecutor` runs.
func makeHandler(bytes: [UInt8], nameId: UInt16 = 0, localCount: Int = 0) throws -> HandlerDef {
    let bytecodeArray = try bytes.withParserSpan { span -> [Bytecode] in
        var array: [Bytecode] = []
        while !span.isEmpty {
            array.append(try Bytecode(parsing: &span))
        }
        return array
    }
    return HandlerDef(
        nameId: nameId, bytecodeArray: bytecodeArray, argumentNameIds: [],
        localNameIds: Array(repeating: 0, count: localCount), globalNameIds: [])
}

/// Assembles a minimal handler + script chunk from hand-encoded bytecode and
/// constructs an executor for it, so each fixture only needs to state its
/// bytes and whichever pieces of context it actually exercises.
func makeExecutor(
    bytes: [UInt8],
    names: [String] = [],
    args: [LingoValue] = [],
    literals: [LiteralValue] = [],
    localCount: Int = 0,
    receiver: LingoObject? = nil,
    host: LingoVMHost? = nil,
    handlers: [HandlerDef] = []
) throws -> LingoVMExecutor {
    let bytecodeArray = try bytes.withParserSpan { span -> [Bytecode] in
        var array: [Bytecode] = []
        while !span.isEmpty {
            array.append(try Bytecode(parsing: &span))
        }
        return array
    }
    let handler = HandlerDef(
        nameId: 0, bytecodeArray: bytecodeArray, argumentNameIds: [],
        localNameIds: Array(repeating: 0, count: localCount), globalNameIds: [])
    let chunk = ScriptChunk(
        scriptNumber: 1, literals: literals, handlers: handlers + [handler], propertyNameIDs: [],
        propertyDefaults: [:])
    return LingoVMExecutor(
        handler: handler, chunk: chunk, names: names, args: args, receiver: receiver, host: host,
        version: 500, multiplier: 8, depth: 0)
}

/// A minimal `LingoObject` subclass for exercising property/method dispatch
/// without any real Director object behind it.
final class TestReceiver: LingoObject {
    var properties: [String: LingoValue] = [:]
    var lastMethodCall: (name: String, args: [LingoValue])?

    override func getProperty(_ name: String) -> LingoValue {
        properties[name] ?? .void
    }

    override func setProperty(_ name: String, value: LingoValue) {
        properties[name] = value
    }

    override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
        lastMethodCall = (name, args)
        return .string("called:\(name)")
    }
}
