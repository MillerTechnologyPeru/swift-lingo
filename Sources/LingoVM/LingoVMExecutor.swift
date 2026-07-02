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

        case .getGlobal, .getGlobal2:
            push(LingoEnvironment.shared.getGlobal(getName(obj)))

        case .setGlobal, .setGlobal2:
            LingoEnvironment.shared.setGlobal(getName(obj), try pop())

        case .getProp:
            push(receiver?.getProperty(getName(obj)) ?? .void)

        case .setProp:
            let value = try pop()
            receiver?.setProperty(getName(obj), value: value)

        case .getParam:
            push(args[safe: variableSlotIndex(obj)] ?? .void)

        case .setParam:
            let value = try pop()
            let index = variableSlotIndex(obj)
            while args.count <= index { args.append(.void) }
            args[index] = value

        case .getLocal:
            push(locals[safe: variableSlotIndex(obj)] ?? .void)

        case .setLocal:
            let value = try pop()
            let index = variableSlotIndex(obj)
            if locals.indices.contains(index) {
                locals[index] = value
            }

        case .getTopLevelProp:
            // Not distinguished from a plain global lookup — the decompiler
            // doesn't distinguish it from `Var` either.
            push(LingoEnvironment.shared.getGlobal(getName(obj)))

        case .pushVarRef:
            // Resolves to the variable's current value rather than a live
            // reference — see the `LingoVMHost`-adjacent trade-off note on
            // `LingoVM`. Globals are the common case for a named var-ref.
            push(LingoEnvironment.shared.getGlobal(getName(obj)))

        case .pushChunkVarRef:
            push(try readVar(varType: obj))

        case .jmp:
            bytecodeIndex = try resolveJumpTarget(pos: bytecode.pos, offset: obj)
            return .jump

        case .jmpIfZ:
            let condition = try pop()
            if !condition.asBool() {
                bytecodeIndex = try resolveJumpTarget(pos: bytecode.pos, offset: obj)
                return .jump
            }

        case .endRepeat:
            // The one opcode whose target is *behind* the current position,
            // so its offset is subtracted rather than added — unlike every
            // other jump opcode.
            bytecodeIndex = try resolveJumpTarget(pos: bytecode.pos, offset: obj, subtract: true)
            return .jump

        case .ret, .retFactory:
            // Whatever's on top of the stack when `Ret` fires is the return
            // value — `return expr` compiles to pushing `expr` immediately
            // before `Ret`, `exit`/an implicit end-of-handler return leaves
            // nothing meaningful behind, hence the `.void` default. No need
            // to special-case "is this the last instruction" the way the
            // decompiler does purely for source reconstruction.
            returnValue = stack.popLast() ?? .void
            return .stop

        case .localCall:
            let argList = try pop()
            let index = Int(obj)
            guard let targetHandler = chunk.handlers[safe: index] else {
                throw LingoVMError.unknownLocalHandler(index)
            }
            let result = try LingoVM.call(
                handler: targetHandler, chunk: chunk, names: names, args: argList.asSequence(),
                receiver: receiver, host: host, version: version, multiplier: multiplier,
                depth: depth + 1)
            push(result)

        case .extCall, .tellCall:
            // `tellCall` targets a different window's message queue in the
            // reference implementation; the decompiler doesn't distinguish
            // it from `extCall` either, so this collapses to the same
            // named-global dispatch.
            let name = getName(obj)
            let argList = try pop()
            push(LingoEnvironment.shared.callGlobal(name, args: argList.asSequence()))

        case .objCallV4:
            let argList = try pop()
            let object = try readVar(varType: obj)
            push(object.dynamicallyCall(withArguments: argList.asSequence()))

        case .objCall:
            let method = getName(obj)
            let argList = try pop()
            push(dispatchObjCall(method: method, argList: argList))

        case .getMovieProp:
            push(host?.movie.getProperty(getName(obj)) ?? .void)

        case .setMovieProp:
            let value = try pop()
            host?.movie.setProperty(getName(obj), value: value)

        case .getObjProp, .getChainedProp:
            let object = try pop()
            if case .object(let target) = object {
                push(target.getProperty(getName(obj)))
            } else {
                push(.void)
            }

        case .setObjProp:
            let value = try pop()
            let object = try pop()
            if case .object(let target) = object {
                target.setProperty(getName(obj), value: value)
            }

        case .get:
            let propId = try pop()
            push(try readV4Property(propertyType: obj, propertyID: Int32(propId.asInteger() ?? 0)))

        case .set:
            let propId = try pop()
            let value = try pop()
            try setV4Property(propertyType: obj, propertyID: Int32(propId.asInteger() ?? 0), value: value)

        default:
            throw LingoVMError.unknownOpcode(bytecode.opcode)
        }

        return .advance
    }

    /// Recognizes the handful of built-in list methods with dedicated
    /// `LingoValue` primitives (mirroring the same special-casing the
    /// decompiler applies for readability); anything else dispatches
    /// generically to the receiver's `callMethod`, matching how `ObjCall`'s
    /// argument list always carries the receiver as its first element.
    ///
    /// `getProp`/`getPropRef`/`setProp`/`setContents*`/`hilite`/`delete` —
    /// also special-cased by the decompiler — are deferred: the first four
    /// need either list double-index ranges or a live variable reference
    /// (see the `PushVarRef` trade-off), and the last two need the chunk
    /// support `DeleteChunk`/`HiliteChunk` add in a later step.
    private func dispatchObjCall(method: String, argList: LingoValue) -> LingoValue {
        let args = argList.asSequence()
        let nargs = args.count

        switch (method, nargs) {
        case ("getAt", 2):
            return args[0][args[1]]
        case ("setAt", 3):
            args[0].setElement(index: args[1], value: args[2])
            return .void
        case ("count", 2):
            if case .symbol(let propName) = args[1], case .object(let object) = args[0] {
                return object.getProperty(propName).count
            }
        default:
            break
        }

        guard let first = args.first, case .object(let target) = first else { return .void }
        return target.callMethod(method, args: Array(args.dropFirst()))
    }

    // MARK: - Director 4 numbered properties (`Get`/`Set`)

    private func chunkTypeName(_ id: Int32) -> String {
        switch id {
        case 1: return "char"
        case 2: return "word"
        case 3: return "item"
        case 4: return "line"
        default: return "char"
        }
    }

    /// Pops the 8-value chunk-range stack contract Director always pushes
    /// before a chunk-typed expression (char/word/item/line, each a
    /// first/last pair), returning whichever range is non-zero — checked
    /// outermost-first (line, then item, then word, then char), matching the
    /// priority order `LingoBytecode`'s decompiler-side `readChunkRef` uses.
    /// `nil` means no range was specified.
    private func popChunkRangeSelector() throws -> (type: String, first: LingoValue, last: LingoValue)? {
        let lastLine = try pop()
        let firstLine = try pop()
        let lastItem = try pop()
        let firstItem = try pop()
        let lastWord = try pop()
        let firstWord = try pop()
        let lastChar = try pop()
        let firstChar = try pop()

        func isNonZero(_ value: LingoValue) -> Bool {
            if case .integer(let v) = value { return v != 0 }
            return false
        }

        if isNonZero(firstLine) { return ("line", firstLine, lastLine) }
        if isNonZero(firstItem) { return ("item", firstItem, lastItem) }
        if isNonZero(firstWord) { return ("word", firstWord, lastWord) }
        if isNonZero(firstChar) { return ("char", firstChar, lastChar) }
        return nil
    }

    /// Director 4's `Get` opcode addresses "the property of object" through
    /// one flat, versioned numbering scheme (movie properties, chunk counts,
    /// menu/sound/sprite properties, member properties, ...) rather than the
    /// named-property opcodes later versions use. Mirrors
    /// `LingoBytecode`'s decompiler-side `readV4Property`, but resolves real
    /// values through `host` instead of building AST nodes.
    private func readV4Property(propertyType: Int64, propertyID: Int32) throws -> LingoValue {
        switch propertyType {
        case 0x00:
            if propertyID <= 0x0b {
                return host?.movie.getProperty(PropertyNames.movieProperty(propertyID)) ?? .void
            }
            let string = try pop()
            return string.lastChunk(chunkTypeName(propertyID - 0x0b))

        case 0x01:
            let string = try pop()
            return string.chunkCount(chunkTypeName(propertyID))

        case 0x02:
            let menuId = try pop()
            return host?.menu(menuId)?.getProperty(
                PropertyNames.menuProperty(UInt32(bitPattern: propertyID))) ?? .void

        case 0x03:
            let menuId = try pop()
            _ = try pop()  // itemId — no dedicated per-item host hook; resolves through the menu itself
            return host?.menu(menuId)?.getProperty(
                PropertyNames.menuItemProperty(UInt32(bitPattern: propertyID))) ?? .void

        case 0x04:
            let soundId = try pop()
            return host?.sound(soundId)?.getProperty(
                PropertyNames.soundProperty(UInt32(bitPattern: propertyID))) ?? .void

        case 0x05:
            return .void  // resource property: unused by the reference implementation too

        case 0x06:
            let spriteId = try pop()
            return host?.sprite(spriteId)?.getProperty(
                PropertyNames.spriteProperty(UInt32(bitPattern: propertyID))) ?? .void

        case 0x07:
            return host?.movie.getProperty(PropertyNames.animationProperty(propertyID)) ?? .void

        case 0x08:
            let propName = PropertyNames.animation2Property(propertyID)
            if propertyID == 0x02, version >= 500 {
                _ = try pop()  // castLib id — not distinguished from the movie-wide total
            }
            return host?.movie.getProperty(propName) ?? .void

        case 0x09...0x15:
            let propName = PropertyNames.memberProperty(propertyID)
            let castId: LingoValue? = version >= 500 ? try pop() : nil
            let memberId = try pop()
            guard let member = host?.member(memberId, castLib: castId) else { return .void }
            let propValue = member.getProperty(propName)
            if propertyType == 0x0a || propertyType == 0x0c || propertyType == 0x15 {
                if let range = try popChunkRangeSelector() {
                    return propValue.chunk(range.type, start: range.first, end: range.last)
                }
            }
            return propValue

        default:
            return .void
        }
    }

    /// The `Set` counterpart of `readV4Property` — mirrors the same operand
    /// shape (both opcodes decode identically in the decompiler too; `Set`
    /// just writes where `Get` reads) for every property namespace that's
    /// actually settable.
    private func setV4Property(propertyType: Int64, propertyID: Int32, value: LingoValue) throws {
        switch propertyType {
        case 0x00:
            if propertyID <= 0x0b {
                host?.movie.setProperty(PropertyNames.movieProperty(propertyID), value: value)
            }

        case 0x02:
            let menuId = try pop()
            host?.menu(menuId)?.setProperty(
                PropertyNames.menuProperty(UInt32(bitPattern: propertyID)), value: value)

        case 0x03:
            let menuId = try pop()
            _ = try pop()  // itemId
            host?.menu(menuId)?.setProperty(
                PropertyNames.menuItemProperty(UInt32(bitPattern: propertyID)), value: value)

        case 0x04:
            let soundId = try pop()
            host?.sound(soundId)?.setProperty(
                PropertyNames.soundProperty(UInt32(bitPattern: propertyID)), value: value)

        case 0x06:
            let spriteId = try pop()
            host?.sprite(spriteId)?.setProperty(
                PropertyNames.spriteProperty(UInt32(bitPattern: propertyID)), value: value)

        case 0x07:
            host?.movie.setProperty(PropertyNames.animationProperty(propertyID), value: value)

        case 0x08:
            let propName = PropertyNames.animation2Property(propertyID)
            if propertyID == 0x02, version >= 500 {
                _ = try pop()
            }
            host?.movie.setProperty(propName, value: value)

        case 0x09...0x15:
            let propName = PropertyNames.memberProperty(propertyID)
            let castId: LingoValue? = version >= 500 ? try pop() : nil
            let memberId = try pop()
            guard let member = host?.member(memberId, castLib: castId) else { return }
            if propertyType == 0x0a || propertyType == 0x0c || propertyType == 0x15,
                let range = try popChunkRangeSelector()
            {
                let updated = member.getProperty(propName).settingChunk(
                    range.type, start: range.first, end: range.last, value: value)
                member.setProperty(propName, value: updated)
            } else {
                member.setProperty(propName, value: value)
            }

        default:
            break
        }
    }

    // MARK: - Control flow

    /// Resolves a jump's byte-position offset to a bytecode-array index via
    /// `bytecodePosMap`. Every loop/branch construct (`if`, `repeat while`,
    /// `repeat with`, `case`, `exit repeat`, `next repeat`) compiles down to
    /// nothing but `Jmp`/`JmpIfZ`/`EndRepeat`, so — unlike the decompiler,
    /// which has to identify *which* source construct produced a given jump
    /// to reconstruct readable text — execution never needs to know which
    /// kind of loop or branch it's in. It just jumps.
    private func resolveJumpTarget(pos: Int, offset: Int64, subtract: Bool = false) throws -> Int {
        let targetPos = subtract ? pos - Int(offset) : pos + Int(offset)
        guard let targetIndex = bytecodePosMap[targetPos] else {
            throw LingoVMError.invalidJumpTarget(targetPos)
        }
        return targetIndex
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

    // MARK: - Variable resolution

    /// Local/argument slot indices are scaled by a version-dependent
    /// multiplier in the raw bytecode operand (matching how the decompiler's
    /// `getLocalName`/`getArgumentName` decode the same encoding).
    private func variableSlotIndex(_ obj: Int64) -> Int {
        Int(UInt32(truncatingIfNeeded: obj) / multiplier)
    }

    /// Resolves a variable reference of the given kind (global/property,
    /// argument, local, or field), popping whichever operands that kind
    /// needs. Used by opcodes that encode the variable dynamically via the
    /// stack rather than through their own `obj` operand (`PushChunkVarRef`,
    /// and — in later steps — `Put`/`PutChunk`/`DeleteChunk`).
    func readVar(varType: Int64) throws -> LingoValue {
        let castId: LingoValue? = (varType == 0x6 && version >= 500) ? try pop() : nil
        let id = try pop()

        switch varType {
        case 0x1, 0x2, 0x3:
            return id
        case 0x4:
            guard let raw = id.asInteger() else { return .void }
            return args[safe: variableSlotIndex(Int64(raw))] ?? .void
        case 0x5:
            guard let raw = id.asInteger() else { return .void }
            return locals[safe: variableSlotIndex(Int64(raw))] ?? .void
        case 0x6:
            guard let object = host?.member(id, castLib: castId) else { return .void }
            return .object(object)
        default:
            return .void
        }
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
