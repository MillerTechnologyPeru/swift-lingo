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
    let environment: LingoEnvironment
    let version: UInt16
    let multiplier: UInt32
    let depth: Int

    var locals: [LingoValue]
    var stack: [LingoValue] = []
    var bytecodeIndex: Int = 0
    var returnValue: LingoValue = .void
    let bytecodePosMap: [Int: Int]

    /// The `tell`-block target currently in effect, if any — pushed by
    /// `StartTell` (resolved through `host.window(_:)`) and popped by
    /// `EndTell`, so nested `tell` blocks stay correctly balanced even when
    /// an inner block's window fails to resolve (`nil` is still pushed, not
    /// skipped, to keep every `EndTell` popping exactly what its matching
    /// `StartTell` pushed).
    var tellStack: [LingoObject?] = []

    /// Argument lists built by `PushArgListNoRet` — the compiler's mark for
    /// a call made as a statement, whose result nothing consumes. A call
    /// fed one of these leaves nothing on the stack. Pushing anyway would
    /// silently grow the stack by one per statement call, which is fatal
    /// inside `repeat with x in list`: that loop keeps its list, count and
    /// counter on the stack and reaches them by `Peek` depth, so a stray
    /// value between them and the top means `add 1` bumps the stray, not
    /// the counter, and the loop never ends. Keyed by list identity because
    /// the arg list is a reference and identity is all a call sees.
    var noReturnArgLists: Set<ObjectIdentifier> = []

    init(
        handler: HandlerDef,
        chunk: ScriptChunk,
        names: [String],
        args: [LingoValue],
        receiver: LingoObject?,
        host: LingoVMHost?,
        environment: LingoEnvironment,
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
        self.environment = environment
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
            let list = LingoValue.list(try popArguments(count: Int(obj)))
            if case .listType(let raw) = list { noReturnArgLists.insert(ObjectIdentifier(raw)) }
            push(list)

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
            push(environment.getGlobal(getName(obj)))

        case .setGlobal, .setGlobal2:
            environment.setGlobal(getName(obj), try pop())

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
            push(environment.getGlobal(getName(obj)))

        case .pushVarRef:
            // Pushes the variable's *name*, not its value — matching the
            // decompiler's own `Datum.varRef(name)` modeling. `Put`/
            // `PutChunk`/`DeleteChunk` need the name to identify where to
            // write back to; anything that wants the current value instead
            // reads through the name itself afterward.
            push(.symbol(getName(obj)))

        case .pushChunkVarRef:
            // Unlike `readVar`, resolves to a write-back-capable reference
            // (see `readVarReference`) — needed so `ObjCall` built-ins like
            // `delete`/`setContents*` can mutate whatever this points to,
            // not just read its current value.
            push(try readVarReference(varType: obj))

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
                receiver: receiver, host: host, environment: environment, version: version,
                multiplier: multiplier, depth: depth + 1)
            pushResult(result, of: argList)

        case .extCall:
            let name = getName(obj)
            let argList = try pop()
            // `return expr` compiles to a named call rather than an opcode:
            // the value is pushed as this call's single argument, and the
            // `Ret` that follows expects the handler to have finished
            // already. Dispatching it as an ordinary global would answer
            // VOID and leave `Ret` to pop that instead — every `return
            // expr` in the movie would evaluate to VOID.
            if name.caseInsensitiveEquals("return") {
                returnValue = argList.asSequence().first ?? .void
                return .stop
            }
            pushResult(environment.callGlobal(name, args: argList.asSequence()), of: argList)

        case .tellCall:
            // Inside a `tell` block, a message send redirects to the
            // block's target window instead of the movie's normal global
            // dispatch — matching `tellStack`'s innermost active target, if
            // its window resolved to an object. Outside any `tell` block
            // (or when the window didn't resolve), this degrades to the
            // same named-global dispatch as `ExtCall`.
            let name = getName(obj)
            let argList = try pop()
            if let target = tellStack.last, let target {
                pushResult(target.callMethod(name, args: argList.asSequence()), of: argList)
            } else {
                pushResult(environment.callGlobal(name, args: argList.asSequence()), of: argList)
            }

        case .objCallV4:
            let argList = try pop()
            let object = try readVar(varType: obj)
            pushResult(object.dynamicallyCall(withArguments: argList.asSequence()), of: argList)

        case .objCall:
            let method = getName(obj)
            let argList = try pop()
            pushResult(dispatchObjCall(method: method, argList: argList), of: argList)

        case .getMovieProp:
            push(host?.movie.getProperty(getName(obj)) ?? .void)

        case .setMovieProp:
            let value = try pop()
            host?.movie.setProperty(getName(obj), value: value)

        case .getObjProp, .getChainedProp:
            let object = try pop()
            let name = getName(obj)
            if case .object(let target) = object {
                push(target.getProperty(name))
            } else if case .propertyListType = object {
                // `glob.download_manager` — dot syntax on a property list is
                // a key lookup, and a chain like `glob.player.manager` is
                // just this repeated.
                push(object.listGetAProp(.symbol(name)))
            } else if name.caseInsensitiveEquals("count") {
                push(object.count)
            } else if let component = LingoBuiltins.geometryProperty(of: object, named: name) {
                // `p.locH`, `r.bottom` — points and rects are lists here.
                push(component)
            } else if case .string(let text) = object, name.caseInsensitiveEquals("length") {
                // `L.length` — string length as a property.
                push(.integer(text.count))
            } else {
                push(.void)
            }

        case .setObjProp:
            let value = try pop()
            let object = try pop()
            let name = getName(obj)
            if case .object(let target) = object {
                target.setProperty(name, value: value)
            } else if case .propertyListType = object {
                object.listSetAProp(.symbol(name), value)
            }

        case .get:
            let propId = try pop()
            push(try readV4Property(propertyType: obj, propertyID: Int32(propId.asInteger() ?? 0)))

        case .set:
            let propId = try pop()
            let value = try pop()
            try setV4Property(propertyType: obj, propertyID: Int32(propId.asInteger() ?? 0), value: value)

        case .joinStr:
            let b = try pop()
            let a = try pop()
            push(a.concat(b))

        case .joinPadStr:
            let b = try pop()
            let a = try pop()
            push(a.concatSpace(b))

        case .containsStr, .contains0Str:
            // The reference distinguishes these by the operands' static
            // type (string vs. list); `LingoValue.contains` already
            // dispatches on the runtime value for both, so one
            // implementation covers both opcodes.
            let b = try pop()
            let a = try pop()
            push(a.contains(b))

        case .getChunk:
            let string = try pop()
            if let range = try popChunkRangeSelector() {
                push(string.chunk(range.type, start: range.first, end: range.last))
            } else {
                push(string)
            }

        case .getField:
            let castId: LingoValue? = version >= 500 ? try pop() : nil
            let fieldId = try pop()
            if let object = host?.member(fieldId, castLib: castId) {
                push(.object(object))
            } else {
                push(.void)
            }

        case .put:
            // Operand pop order matches the decompiler exactly: the
            // variable-identifying operands first (via `readVarTarget`),
            // the value last.
            let target = try readVarTarget(varType: obj & 0xF)
            let value = try pop()
            if let target {
                switch (obj >> 4) & 0xF {
                case 1: writeVariable(target, value: value)  // into
                case 2: writeVariable(target, value: readVariable(target).concat(value))  // after
                case 3: writeVariable(target, value: value.concat(readVariable(target)))  // before
                default: writeVariable(target, value: value)
                }
            }

        case .putChunk:
            let target = try readVarTarget(varType: obj & 0xF)
            let range = try popChunkRangeSelector()
            let value = try pop()
            if let target, let range {
                let current = readVariable(target)
                let existingChunk = current.chunk(range.type, start: range.first, end: range.last)
                let newChunkContent: LingoValue
                switch (obj >> 4) & 0xF {
                case 2: newChunkContent = existingChunk.concat(value)  // after
                case 3: newChunkContent = value.concat(existingChunk)  // before
                default: newChunkContent = value  // into
                }
                writeVariable(
                    target,
                    value: current.settingChunk(
                        range.type, start: range.first, end: range.last, value: newChunkContent))
            }

        case .deleteChunk:
            let target = try readVarTarget(varType: obj)
            let range = try popChunkRangeSelector()
            if let target, let range {
                // Deleting is not putting EMPTY into the chunk: it takes an
                // adjoining separator with it so the neighbors close ranks.
                let current = readVariable(target)
                writeVariable(
                    target,
                    value: current.deletingChunk(range.type, start: range.first, end: range.last))
            }

        case .hiliteChunk:
            let castId: LingoValue? = version >= 500 ? try pop() : nil
            let fieldId = try pop()
            let range = try popChunkRangeSelector()
            if let range, let member = host?.member(fieldId, castLib: castId) {
                host?.hilite(member, type: range.type, first: range.first, last: range.last)
            }

        case .ontoSpr:
            let second = try pop()
            let first = try pop()
            push(.integer(resolveSpriteCollision(first, second, using: { host?.spriteIntersects($0, $1) }) ? 1 : 0))

        case .intoSpr:
            let second = try pop()
            let first = try pop()
            push(.integer(resolveSpriteCollision(first, second, using: { host?.spriteWithin($0, $1) }) ? 1 : 0))

        case .theBuiltin:
            _ = try pop()  // empty arglist
            push(host?.movie.getProperty(getName(obj)) ?? .void)

        case .newObj:
            let objArgs = try pop()
            if let object = host?.makeObject(scriptName: getName(obj), args: objArgs.asSequence()) {
                push(.object(object))
            } else {
                push(.void)
            }

        case .startTell:
            let window = try pop()
            tellStack.append(host?.window(window))

        case .endTell:
            _ = tellStack.popLast()

        case .callJavaScript:
            // Unimplemented in the reference too (warning-only stub) — no
            // operands are known to pop here, so this is a pure no-op.
            break

        default:
            throw LingoVMError.unknownOpcode(bytecode.opcode)
        }

        return .advance
    }

    /// Recognizes the handful of built-in list/property methods with
    /// dedicated `LingoValue` primitives (mirroring the same special-casing
    /// the decompiler applies for readability); anything else dispatches
    /// generically to the receiver's `callMethod`, matching how `ObjCall`'s
    /// argument list always carries the receiver as its first element.
    ///
    /// `delete`/`setContents*` mutate the live reference `PushChunkVarRef`
    /// produces (see `readVarReference`) via its `"value"` property, rather
    /// than falling through to the generic dispatch above — `args[0]` for
    /// these is a variable reference, not a receiver object, so treating it
    /// as one and calling a method literally named e.g. `"setContents"` on
    /// it would silently do the wrong thing on the rare occasion `args[0]`
    /// happens to itself be an ordinary object.
    ///
    /// `hilite` is still deferred with an explicit no-op — it needs a host
    /// hook carrying position information (which field/range to highlight)
    /// that doesn't exist yet.
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
            // `t.line.count` — a chunk-collection count on a string.
            if case .string = args[0], case .symbol(let chunkType) = args[1],
                Self.isChunkType(chunkType)
            {
                return args[0].chunkCount(chunkType)
            }
        case ("getProp", 3), ("getProp", 4), ("getPropRef", 3), ("getPropRef", 4):
            if case .object(let object) = args[0], case .symbol(let propName) = args[1] {
                let value = object.getProperty(propName)
                return nargs == 4 ? value.getRange(start: args[2], end: args[3]) : value[args[2]]
            }
            // `t.line[n]` and `t.char[a..b]` — chunk-collection indexing on
            // a string resolves to the chunk expression itself.
            if case .string = args[0], case .symbol(let chunkType) = args[1],
                Self.isChunkType(chunkType)
            {
                return args[0].chunk(
                    chunkType, start: args[2], end: nargs == 4 ? args[3] : nil)
            }
            // `plist.key[n]` / `plist.key[a..b]` with a property list at the
            // root — the download manager's
            // `displaysprites.loading_msg[1].member.text = ...`. The key
            // selects the inner list; the rest indexes into it.
            if args[0].isList, nargs == 3 {
                return args[0].listGetAProp(args[1])[args[2]]
            }
        case ("setProp", 4):
            if case .object(let object) = args[0], case .symbol(let propName) = args[1] {
                object.getProperty(propName).setElement(index: args[2], value: args[3])
                return .void
            }
            // `glob.PLAYER[#play_manager] = v` — a two-level set whose root
            // is itself a property list: fetch the inner collection (a
            // reference), then set into it.
            if args[0].isList {
                args[0][args[1]].setElement(index: args[2], value: args[3])
                return .void
            }
        case ("setProp", 5):
            if case .object(let object) = args[0], case .symbol(let propName) = args[1] {
                let current = object.getProperty(propName)
                object.setProperty(
                    propName, value: current.settingRange(start: args[2], end: args[3], value: args[4]))
                return .void
            }
        case ("delete", 1):
            // No separate chunk-range operands travel with this shape
            // (unlike the dedicated `DeleteChunk` opcode, which pops its own
            // char/word/item/line range selector) — a bare `nargs == 1`
            // means `args[0]` is the whole referenced location, so this
            // clears it entirely rather than a sub-range within it.
            if case .object(let ref) = args[0] {
                ref.setProperty("value", value: .string(""))
            }
            return .void
        case ("setContents", 2), ("setContentsAfter", 2), ("setContentsBefore", 2):
            if case .object(let ref) = args[0] {
                let current = ref.getProperty("value")
                switch method {
                case "setContentsAfter": ref.setProperty("value", value: current.concat(args[1]))
                case "setContentsBefore": ref.setProperty("value", value: args[1].concat(current))
                default: ref.setProperty("value", value: args[1])
                }
            }
            return .void
        case ("hilite", 1):
            return .void
        default:
            break
        }

        // List commands arrive here as ordinary method calls on a list
        // receiver, which is neither an object nor one of the shapes above.
        if let receiver = args.first,
            let result = Self.dispatchListCall(
                method: method, receiver: receiver, args: Array(args.dropFirst()))
        {
            return result
        }

        guard let first = args.first, case .object(let target) = first else { return .void }
        return target.callMethod(method, args: Array(args.dropFirst()))
    }

    /// The four string chunk collections (`char`/`word`/`item`/`line`).
    static func isChunkType(_ name: String) -> Bool {
        name.caseInsensitiveEquals("char") || name.caseInsensitiveEquals("word")
            || name.caseInsensitiveEquals("item") || name.caseInsensitiveEquals("line")
            || name.caseInsensitiveEquals("paragraph")
    }

    /// Routes Lingo's list commands to their `LingoValue` implementations.
    ///
    /// Returns `nil` when `method` isn't a list command or `receiver` isn't a
    /// list, so the caller can fall through to ordinary object dispatch —
    /// an object is free to define its own `add`, and that has to keep
    /// working.
    static func dispatchListCall(
        method: String, receiver: LingoValue, args: [LingoValue]
    ) -> LingoValue? {
        guard receiver.isList else { return nil }
        func argument(_ index: Int) -> LingoValue { index < args.count ? args[index] : .void }

        switch method.asciiLowercased() {
        case "add": receiver.listAdd(argument(0))
        case "append": receiver.listAppend(argument(0))
        case "addat": receiver.listAddAt(argument(0), argument(1))
        case "deleteat": receiver.listDeleteAt(argument(0))
        case "deleteone": receiver.listDeleteOne(argument(0))
        case "deleteprop": receiver.listDeleteProp(argument(0))
        case "addprop": receiver.listAddProp(argument(0), argument(1))
        case "setaprop": receiver.listSetAProp(argument(0), argument(1))
        case "sort": receiver.listSort()
        case "getpos": return receiver.listGetPos(argument(0))
        case "getone": return receiver.listGetOne(argument(0))
        case "getlast": return receiver.listGetLast()
        case "getaprop": return receiver.listGetAProp(argument(0))
        case "getpropat": return receiver.listGetPropAt(argument(0))
        case "findpos": return receiver.listFindPos(argument(0))
        case "duplicate": return receiver.listDuplicate()
        case "count": return receiver.count
        case "getat": return receiver[argument(0)]
        case "setat":
            receiver.setElement(index: argument(0), value: argument(1))
        default:
            // Anything else aimed at a property list is a key read —
            // `glob.download_manager` reaches the VM as a no-argument call
            // named after the key. Linear lists have no such spelling, so
            // they fall through to ordinary dispatch.
            if case .propertyListType = receiver, args.isEmpty {
                return receiver.listGetAProp(.symbol(method))
            }
            return nil
        }
        return .void
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
    /// Pushes a call's result unless its argument list was built by
    /// `PushArgListNoRet` — a statement call, whose result is dropped.
    private func pushResult(_ result: LingoValue, of argList: LingoValue) {
        if case .listType(let raw) = argList,
            noReturnArgLists.remove(ObjectIdentifier(raw)) != nil
        {
            return
        }
        push(result)
    }

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
    /// argument, local, or field) to its *current value*, popping whichever
    /// operands that kind needs. Used by `ObjCallV4`, which treats the
    /// result as something to *call* (`dynamicallyCall`), not a write-back
    /// target — this must keep resolving to a plain value.
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

    /// A live reference to a variable/property/chunk-owning location,
    /// exposed as a `LingoObject` so it flows through the value stack via
    /// the existing `.object(...)` case with no change to `LingoValue`
    /// itself. `"value"` is its only real property — read the current
    /// value, write a new one. Meant to be short-lived: created by
    /// `PushChunkVarRef` and consumed by the very next `ObjCall` in the
    /// same instruction sequence, never stored long-term.
    private final class VariableReferenceBox: LingoObject {
        private let read: () -> LingoValue
        private let write: (LingoValue) -> Void

        init(environment: LingoEnvironment, read: @escaping () -> LingoValue, write: @escaping (LingoValue) -> Void) {
            self.read = read
            self.write = write
            super.init(environment: environment)
        }

        override func getProperty(_ name: String) -> LingoValue {
            name == "value" ? read() : super.getProperty(name)
        }

        override func setProperty(_ name: String, value: LingoValue) {
            if name == "value" {
                write(value)
            } else {
                super.setProperty(name, value: value)
            }
        }
    }

    /// Resolves a variable reference of the given kind to a live,
    /// write-back-capable `VariableReferenceBox` instead of a plain value —
    /// `readVar`'s value-only resolution can't express "write back here."
    /// Used by `PushChunkVarRef` specifically, so a chunk/variable
    /// reference pushed as an `ObjCall` argument (e.g. for `delete`/
    /// `setContents*`) can still be mutated once popped from the arg list.
    /// Mirrors `readVarTarget`'s exact pop order and per-kind logic.
    private func readVarReference(varType: Int64) throws -> LingoValue {
        let castId: LingoValue? = (varType == 0x6 && version >= 500) ? try pop() : nil
        let id = try pop()

        switch varType {
        case 0x1:
            guard case .symbol(let name) = id else { return .void }
            return .object(
                VariableReferenceBox(
                    environment: environment,
                    read: { [environment] in environment.getGlobal(name) },
                    write: { [environment] in environment.setGlobal(name, $0) }))
        case 0x2, 0x3:
            guard case .symbol(let name) = id else { return .void }
            return .object(
                VariableReferenceBox(
                    environment: environment,
                    read: { [weak receiver] in receiver?.getProperty(name) ?? .void },
                    write: { [weak receiver] in receiver?.setProperty(name, value: $0) }))
        case 0x4:
            guard let raw = id.asInteger() else { return .void }
            let index = variableSlotIndex(Int64(raw))
            return .object(
                VariableReferenceBox(
                    environment: environment,
                    read: { [weak self] in self?.args[safe: index] ?? .void },
                    write: { [weak self] value in
                        guard let self else { return }
                        while self.args.count <= index { self.args.append(.void) }
                        self.args[index] = value
                    }))
        case 0x5:
            guard let raw = id.asInteger() else { return .void }
            let index = variableSlotIndex(Int64(raw))
            return .object(
                VariableReferenceBox(
                    environment: environment,
                    read: { [weak self] in self?.locals[safe: index] ?? .void },
                    write: { [weak self] value in
                        guard let self, self.locals.indices.contains(index) else { return }
                        self.locals[index] = value
                    }))
        case 0x6:
            guard let object = host?.member(id, castLib: castId) else { return .void }
            return .object(
                VariableReferenceBox(
                    environment: environment,
                    read: { object.getProperty("text") },
                    write: { object.setProperty("text", value: $0) }))
        default:
            return .void
        }
    }

    /// A variable's write-back location — a different question from
    /// `readVar`'s "what is this variable's current value?". `Put`/
    /// `PutChunk`/`DeleteChunk` need somewhere to write the result, which
    /// `readVar`'s value-only resolution can't express. A field's location
    /// is represented by its `text` property, matching how field content is
    /// otherwise addressed as a `LingoObject` property.
    enum VariableTarget {
        case global(String)
        case property(String)
        case argument(Int)
        case local(Int)
        case field(LingoObject)
    }

    /// Identifies a write-back target of the given kind, popping whichever
    /// operands that kind needs. Global/property targets are identified by
    /// the *name* a preceding `PushVarRef`-style push already put on the
    /// stack (a `.symbol`), not a resolved value.
    private func readVarTarget(varType: Int64) throws -> VariableTarget? {
        let castId: LingoValue? = (varType == 0x6 && version >= 500) ? try pop() : nil
        let id = try pop()

        switch varType {
        case 0x1:
            if case .symbol(let name) = id { return .global(name) }
            return nil
        case 0x2, 0x3:
            if case .symbol(let name) = id { return .property(name) }
            return nil
        case 0x4:
            guard let raw = id.asInteger() else { return nil }
            return .argument(variableSlotIndex(Int64(raw)))
        case 0x5:
            guard let raw = id.asInteger() else { return nil }
            return .local(variableSlotIndex(Int64(raw)))
        case 0x6:
            guard let object = host?.member(id, castLib: castId) else { return nil }
            return .field(object)
        default:
            return nil
        }
    }

    private func readVariable(_ target: VariableTarget) -> LingoValue {
        switch target {
        case .global(let name): return environment.getGlobal(name)
        case .property(let name): return receiver?.getProperty(name) ?? .void
        case .argument(let index): return args[safe: index] ?? .void
        case .local(let index): return locals[safe: index] ?? .void
        case .field(let object): return object.getProperty("text")
        }
    }

    private func writeVariable(_ target: VariableTarget, value: LingoValue) {
        switch target {
        case .global(let name):
            environment.setGlobal(name, value)
        case .property(let name):
            receiver?.setProperty(name, value: value)
        case .argument(let index):
            while args.count <= index { args.append(.void) }
            args[index] = value
        case .local(let index):
            if locals.indices.contains(index) { locals[index] = value }
        case .field(let object):
            object.setProperty("text", value: value)
        }
    }

    /// `OntoSpr`/`IntoSpr` (sprite collision) resolve entirely through the
    /// host — the VM has no geometry logic of its own. Missing/non-object
    /// operands mean "no collision", matching the reference's own
    /// soft-fail convention.
    private func resolveSpriteCollision(
        _ a: LingoValue, _ b: LingoValue, using test: (LingoObject, LingoObject) -> Bool?
    ) -> Bool {
        guard case .object(let objA) = a, case .object(let objB) = b else { return false }
        return test(objA, objB) ?? false
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
