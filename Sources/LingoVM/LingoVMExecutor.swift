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
        let obj = bytecode.obj

        switch bytecode.opcode {
        case .pushZero:
            push(.integer(0))

        case .pushInt8, .pushInt16, .pushInt32:
            push(.integer(Int(obj)))

        case .pushFloat32:
            let bits = UInt32(truncatingIfNeeded: obj)
            push(.float(Double(Float(bitPattern: bits))))

        case .pushCons:
            let literalId = Int(UInt32(truncatingIfNeeded: obj) / multiplier)
            push(literalValue(at: literalId))

        case .pushSymb:
            push(.symbol(getName(obj)))

        case .pushList:
            let list = try pop()
            push(.list(list.asSequence()))

        case .pushPropList:
            let list = try pop()
            push(.propertyList(propertyListEntries(from: list)))

        case .pushArgList:
            push(.list(try popArguments(count: Int(obj))))

        case .pushArgListNoRet:
            push(.list(try popArguments(count: Int(obj))))

        case .peek:
            let depthFromTop = Int(obj)
            guard depthFromTop < stack.count else { throw LingoVMError.stackUnderflow }
            push(stack[stack.count - 1 - depthFromTop])

        case .pop:
            let count = Int(obj)
            guard stack.count >= count else { throw LingoVMError.stackUnderflow }
            stack.removeLast(count)

        case .swap:
            guard stack.count >= 2 else { throw LingoVMError.stackUnderflow }
            stack.swapAt(stack.count - 1, stack.count - 2)

        case .mul:
            let b = try pop()
            let a = try pop()
            push(a * b)

        case .add:
            let b = try pop()
            let a = try pop()
            push(a + b)

        case .sub:
            let b = try pop()
            let a = try pop()
            push(a - b)

        case .div:
            let b = try pop()
            let a = try pop()
            push(a / b)

        case .mod:
            let b = try pop()
            let a = try pop()
            push(a % b)

        case .inv:
            let a = try pop()
            push(-a)

        case .not:
            let a = try pop()
            push(.integer(a.asBool() ? 0 : 1))

        case .and:
            let b = try pop()
            let a = try pop()
            push(.integer(a.asBool() && b.asBool() ? 1 : 0))

        case .or:
            let b = try pop()
            let a = try pop()
            push(.integer(a.asBool() || b.asBool() ? 1 : 0))

        case .lt:
            let b = try pop()
            let a = try pop()
            push(a < b)

        case .ltEq:
            let b = try pop()
            let a = try pop()
            push(a <= b)

        case .gt:
            let b = try pop()
            let a = try pop()
            push(a > b)

        case .gtEq:
            let b = try pop()
            let a = try pop()
            push(a >= b)

        case .eq:
            let b = try pop()
            let a = try pop()
            push(a == b)

        case .ntEq:
            let b = try pop()
            let a = try pop()
            push(a != b)

        default:
            throw LingoVMError.unknownOpcode(bytecode.opcode)
        }

        return .advance
    }

    // MARK: - Stack helpers

    func pop() throws -> LingoValue {
        guard let value = stack.popLast() else { throw LingoVMError.stackUnderflow }
        return value
    }

    func push(_ value: LingoValue) {
        stack.append(value)
    }

    /// Pops `count` values in reverse push order, restoring left-to-right
    /// argument order (the last-pushed argument is popped first).
    private func popArguments(count: Int) throws -> [LingoValue] {
        var args: [LingoValue] = []
        args.reserveCapacity(count)
        for _ in 0..<count {
            args.append(try pop())
        }
        return args.reversed()
    }

    /// A property list is a flat, alternating key/value sequence on the
    /// stack (`Datum::PropList` in the literal pool follows the same shape).
    private func propertyListEntries(from value: LingoValue) -> [(key: LingoValue, value: LingoValue)] {
        let items = value.asSequence()
        var entries: [(key: LingoValue, value: LingoValue)] = []
        var i = 0
        while i + 1 < items.count {
            entries.append((key: items[i], value: items[i + 1]))
            i += 2
        }
        return entries
    }

    // MARK: - Name / literal resolution

    func getName(_ id: Int64) -> String {
        names[safe: Int(id)] ?? "UNKNOWN_\(id)"
    }

    private func literalValue(at index: Int) -> LingoValue {
        guard let literal = chunk.literals[safe: index] else { return .void }
        switch literal {
        case .string(let s): return .string(s)
        case .int(let i): return .integer(Int(i))
        case .double(let f): return .float(f)
        case .invalid, .javascript: return .void
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
