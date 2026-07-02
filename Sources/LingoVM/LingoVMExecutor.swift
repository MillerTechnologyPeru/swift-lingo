import LingoBytecode
import LingoRuntime

/// Executes one handler's compiled bytecode as a stack machine. Mirrors the
/// call-frame shape `DecompilerState` already establishes (a position→index
/// jump table built once from `handler.bytecodeArray`), but this one
/// actually runs the opcodes rather than reconstructing readable source from
/// them — its stack holds live `LingoValue`s, not decompiler AST nodes.
final class LingoVMExecutor {
    let handler: HandlerDef
    let chunk: ScriptChunk
    let names: [String]
    let receiver: LingoObject?
    var args: [LingoValue]
    let host: LingoVMHost?
    let version: UInt16
    let multiplier: UInt32
    let depth: Int

    var locals: [LingoValue]
    var stack: [LingoValue] = []
    var bytecodeIndex: Int = 0
    var returnValue: LingoValue = .void
    let bytecodePosMap: [Int: Int]

    init(
        handler: HandlerDef,
        chunk: ScriptChunk,
        names: [String],
        args: [LingoValue],
        receiver: LingoObject?,
        host: LingoVMHost?,
        version: UInt16,
        multiplier: UInt32,
        depth: Int
    ) {
        self.handler = handler
        self.chunk = chunk
        self.names = names
        self.args = args
        self.receiver = receiver
        self.host = host
        self.version = version
        self.multiplier = multiplier
        self.depth = depth
        self.locals = Array(repeating: .void, count: handler.localNameIds.count)

        var posMap: [Int: Int] = [:]
        for (i, bytecode) in handler.bytecodeArray.enumerated() {
            posMap[bytecode.pos] = i
        }
        self.bytecodePosMap = posMap
    }

    enum StepResult {
        case advance
        case jump
        case stop
    }

    func run() throws -> LingoValue {
        guard depth < LingoVM.maxRecursionDepth else { throw LingoVMError.recursionLimitExceeded }
        while bytecodeIndex < handler.bytecodeArray.count {
            switch try step() {
            case .advance: bytecodeIndex += 1
            case .jump: break  // bytecodeIndex already rewritten by the handler
            case .stop: return returnValue
            }
        }
        return returnValue
    }

    /// Executes the single instruction at `bytecodeIndex`. Populated
    /// incrementally as opcode groups are implemented; anything not yet
    /// (or never) recognized is a hard error, not a silent no-op, so gaps
    /// are visible rather than producing quietly-wrong results.
    func step() throws -> StepResult {
        let bytecode = handler.bytecodeArray[bytecodeIndex]
        switch bytecode.opcode {
        default:
            throw LingoVMError.unknownOpcode(bytecode.opcode)
        }
    }

    // MARK: - Stack helpers

    func pop() throws -> LingoValue {
        guard let value = stack.popLast() else { throw LingoVMError.stackUnderflow }
        return value
    }

    func push(_ value: LingoValue) {
        stack.append(value)
    }
}
