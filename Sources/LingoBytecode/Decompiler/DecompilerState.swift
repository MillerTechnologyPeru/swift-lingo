import LingoAST

/// Simulates Director's Lingo bytecode stack machine to reconstruct the
/// structure a compiled handler was originally written in — expressions,
/// assignments, `if`/`repeat`/`case`/`tell` blocks — from its flat opcode
/// stream. This mirrors what a human reading raw stack-machine bytecode
/// would do by hand: track what's been pushed, recognize the handful of
/// bytecode shapes each control-flow construct compiles down to, and walk
/// the jump targets to figure out where blocks begin and end.
final class DecompilerState {
    let handler: HandlerDef
    let chunk: ScriptChunk
    let names: [String]
    let version: UInt16
    let multiplier: UInt32

    /// Expression stack, with bytecode-index provenance kept alongside each
    /// entry so that (later) higher-level tooling can map decompiled output
    /// back to the instructions it came from.
    var stack: [StackEntry] = []

    let rootBlock: BlockNode
    var currentBlock: BlockNode
    var blockStack: [BlockNode] = []
    var blockContextStack: [BlockContext] = []

    var bytecodeTags: [BytecodeInfo]
    var bytecodePosMap: [Int: Int] = [:]

    var currentBytecodeIndex: Int = 0

    init(handler: HandlerDef, chunk: ScriptChunk, names: [String], version: UInt16, multiplier: UInt32) {
        self.handler = handler
        self.chunk = chunk
        self.names = names
        self.version = version
        self.multiplier = multiplier

        let root = BlockNode()
        self.rootBlock = root
        self.currentBlock = root

        var posMap: [Int: Int] = [:]
        for (i, bytecode) in handler.bytecodeArray.enumerated() {
            posMap[bytecode.pos] = i
        }
        self.bytecodePosMap = posMap
        self.bytecodeTags = Array(repeating: BytecodeInfo(), count: handler.bytecodeArray.count)
    }

    // MARK: - Name resolution

    func getName(_ id: Int64) -> String {
        names[safe: Int(id)] ?? "UNKNOWN_\(id)"
    }

    func getLocalName(_ id: Int64) -> String {
        let localIndex = Int(UInt32(truncatingIfNeeded: id) / multiplier)
        if let nameId = handler.localNameIds[safe: localIndex], let name = names[safe: Int(nameId)] {
            return name
        }
        return "local_\(localIndex)"
    }

    func getArgumentName(_ id: Int64) -> String {
        let argIndex = Int(UInt32(truncatingIfNeeded: id) / multiplier)
        if let nameId = handler.argumentNameIds[safe: argIndex], let name = names[safe: Int(nameId)] {
            return name
        }
        return "arg_\(argIndex)"
    }

    // MARK: - Stack

    @discardableResult
    func pop() -> AstNode {
        stack.popLast()?.node ?? .error
    }

    @discardableResult
    func popWithIndices(_ indices: inout [Int]) -> AstNode {
        guard let entry = stack.popLast() else { return .error }
        indices.append(contentsOf: entry.bytecodeIndices)
        return entry.node
    }

    func push(_ node: AstNode) {
        stack.append(StackEntry(node: node, bytecodeIndices: [currentBytecodeIndex]))
    }

    func push(_ node: AstNode, indices: [Int]) {
        var allIndices = indices
        allIndices.append(currentBytecodeIndex)
        stack.append(StackEntry(node: node, bytecodeIndices: allIndices))
    }

    // MARK: - Blocks

    func enterBlock(_ block: BlockNode, context: BlockContext) {
        blockStack.append(currentBlock)
        blockContextStack.append(context)
        currentBlock = block
    }

    @discardableResult
    func exitBlock() -> BlockContext? {
        guard let parent = blockStack.popLast() else { return nil }
        currentBlock = parent
        return blockContextStack.popLast()
    }

    func ancestorLoopStartIndex() -> UInt32? {
        for context in blockContextStack.reversed() {
            if case .loop(let startIndex) = context {
                return startIndex
            }
        }
        return nil
    }

    func ancestorStatementContext() -> BlockContext? {
        blockContextStack.last
    }

    func addStatement(_ node: AstNode, bytecodeIndices: [Int]) {
        currentBlock.addChild(node, bytecodeIndices: bytecodeIndices)
    }

    // MARK: - Loop tagging

    /// A `repeat while`/`repeat with`/`repeat with...in` loop compiles to a
    /// recognizable, fixed shape: a `JmpIfZ` guarding the loop body, an
    /// `EndRepeat` jumping back to re-check the condition, plus (for
    /// counting/list loops) a handful of setup and increment instructions
    /// immediately around those two. This walks every `JmpIfZ`/`EndRepeat`
    /// pair up front, matches it against those known shapes, and tags the
    /// bytecode indices involved so the main decode pass (`translateBytecode`)
    /// can skip the internal bookkeeping and recognize backward jumps as
    /// `exit repeat`/`next repeat` instead of generic, unidentified jumps.
    func tagLoops() {
        let bytecodeArray = handler.bytecodeArray
        for startIndex in 0..<bytecodeArray.count {
            let jmpifz = bytecodeArray[startIndex]
            guard jmpifz.opcode == .jmpIfZ else { continue }

            let jmpPos = jmpifz.pos + Int(jmpifz.obj)
            guard let endIndex = bytecodePosMap[jmpPos] else { continue }
            guard endIndex != 0 else { continue }

            let endRepeat = bytecodeArray[endIndex - 1]
            guard endRepeat.opcode == .endRepeat else { continue }
            guard endRepeat.pos >= Int(endRepeat.obj) else { continue }
            guard (endRepeat.pos - Int(endRepeat.obj)) <= jmpifz.pos else { continue }

            let loopType = identifyLoop(startIndex: startIndex, endIndex: endIndex)
            bytecodeTags[startIndex].tag = loopType

            switch loopType {
            case .repeatWithIn:
                if startIndex >= 7 {
                    for i in (startIndex - 7)..<startIndex {
                        bytecodeTags[i].tag = .skip
                    }
                }
                for i in (startIndex + 1)...min(startIndex + 5, bytecodeArray.count - 1) {
                    bytecodeTags[i].tag = .skip
                }
                if endIndex >= 3 {
                    bytecodeTags[endIndex - 3].tag = .nextRepeatTarget
                    bytecodeTags[endIndex - 3].ownerLoop = UInt32(startIndex)
                    bytecodeTags[endIndex - 2].tag = .skip
                    bytecodeTags[endIndex - 1].tag = .skip
                    bytecodeTags[endIndex - 1].ownerLoop = UInt32(startIndex)
                }
                if endIndex < bytecodeArray.count {
                    bytecodeTags[endIndex].tag = .skip
                }

            case .repeatWithTo, .repeatWithDownTo:
                let endRepeat = bytecodeArray[endIndex - 1]
                if let conditionStartIndex = bytecodePosMap[endRepeat.pos - Int(endRepeat.obj)] {
                    if conditionStartIndex > 0 {
                        bytecodeTags[conditionStartIndex - 1].tag = .skip
                    }
                    bytecodeTags[conditionStartIndex].tag = .skip
                }
                if startIndex > 0 {
                    bytecodeTags[startIndex - 1].tag = .skip
                }
                if endIndex >= 5 {
                    bytecodeTags[endIndex - 5].tag = .nextRepeatTarget
                    bytecodeTags[endIndex - 5].ownerLoop = UInt32(startIndex)
                    bytecodeTags[endIndex - 4].tag = .skip
                    bytecodeTags[endIndex - 3].tag = .skip
                    bytecodeTags[endIndex - 2].tag = .skip
                    bytecodeTags[endIndex - 1].tag = .skip
                    bytecodeTags[endIndex - 1].ownerLoop = UInt32(startIndex)
                }

            case .repeatWhile:
                bytecodeTags[endIndex - 1].tag = .nextRepeatTarget
                bytecodeTags[endIndex - 1].ownerLoop = UInt32(startIndex)

            default:
                break
            }
        }
    }

    func identifyLoop(startIndex: Int, endIndex: Int) -> BytecodeTag {
        if isRepeatWithIn(startIndex: startIndex, endIndex: endIndex) {
            return .repeatWithIn
        }
        guard startIndex >= 1 else { return .repeatWhile }

        let bytecodeArray = handler.bytecodeArray
        let up: Bool
        switch bytecodeArray[startIndex - 1].opcode {
        case .ltEq: up = true
        case .gtEq: up = false
        default: return .repeatWhile
        }

        let endRepeat = bytecodeArray[endIndex - 1]
        let conditionStartPos = endRepeat.pos - Int(endRepeat.obj)
        guard let conditionStartIndex = bytecodePosMap[conditionStartPos] else { return .repeatWhile }
        guard conditionStartIndex >= 1 else { return .repeatWhile }

        let setOp = bytecodeArray[conditionStartIndex - 1].opcode
        let getOp: OpCode
        switch setOp {
        case .setGlobal: getOp = .getGlobal
        case .setGlobal2: getOp = .getGlobal2
        case .setProp: getOp = .getProp
        case .setParam: getOp = .getParam
        case .setLocal: getOp = .getLocal
        default: return .repeatWhile
        }
        let varId = bytecodeArray[conditionStartIndex - 1].obj

        guard bytecodeArray[conditionStartIndex].opcode == getOp,
            bytecodeArray[conditionStartIndex].obj == varId
        else {
            return .repeatWhile
        }
        guard endIndex >= 5 else { return .repeatWhile }

        let expectedInc: Int64 = up ? 1 : -1
        guard bytecodeArray[endIndex - 5].opcode == .pushInt8, bytecodeArray[endIndex - 5].obj == expectedInc
        else {
            return .repeatWhile
        }
        guard bytecodeArray[endIndex - 4].opcode == getOp, bytecodeArray[endIndex - 4].obj == varId else {
            return .repeatWhile
        }
        guard bytecodeArray[endIndex - 3].opcode == .add else { return .repeatWhile }
        guard bytecodeArray[endIndex - 2].opcode == setOp, bytecodeArray[endIndex - 2].obj == varId else {
            return .repeatWhile
        }

        return up ? .repeatWithTo : .repeatWithDownTo
    }

    /// `repeat with x in aList` compiles to a fixed idiom built on `count()`
    /// and `getAt()` calls rather than a dedicated opcode, so recognizing it
    /// means matching that exact instruction sequence around the loop's
    /// `JmpIfZ`/`EndRepeat` pair.
    func isRepeatWithIn(startIndex: Int, endIndex: Int) -> Bool {
        let bytecodeArray = handler.bytecodeArray
        guard startIndex >= 7, startIndex + 5 < bytecodeArray.count else { return false }

        guard bytecodeArray[startIndex - 7].opcode == .peek, bytecodeArray[startIndex - 7].obj == 0 else {
            return false
        }
        guard bytecodeArray[startIndex - 6].opcode == .pushArgList, bytecodeArray[startIndex - 6].obj == 1
        else { return false }
        guard bytecodeArray[startIndex - 5].opcode == .extCall,
            getName(bytecodeArray[startIndex - 5].obj) == "count"
        else { return false }
        guard bytecodeArray[startIndex - 4].opcode == .pushInt8, bytecodeArray[startIndex - 4].obj == 1
        else { return false }
        guard bytecodeArray[startIndex - 3].opcode == .peek, bytecodeArray[startIndex - 3].obj == 0 else {
            return false
        }
        guard bytecodeArray[startIndex - 2].opcode == .peek, bytecodeArray[startIndex - 2].obj == 2 else {
            return false
        }
        guard bytecodeArray[startIndex - 1].opcode == .ltEq else { return false }

        guard bytecodeArray[startIndex + 1].opcode == .peek, bytecodeArray[startIndex + 1].obj == 2 else {
            return false
        }
        guard bytecodeArray[startIndex + 2].opcode == .peek, bytecodeArray[startIndex + 2].obj == 1 else {
            return false
        }
        guard bytecodeArray[startIndex + 3].opcode == .pushArgList, bytecodeArray[startIndex + 3].obj == 2
        else { return false }
        guard bytecodeArray[startIndex + 4].opcode == .extCall,
            getName(bytecodeArray[startIndex + 4].obj) == "getAt"
        else { return false }

        let setOp = bytecodeArray[startIndex + 5].opcode
        guard setOp == .setGlobal || setOp == .setProp || setOp == .setParam || setOp == .setLocal else {
            return false
        }

        guard endIndex >= 3, endIndex < bytecodeArray.count else { return false }
        guard bytecodeArray[endIndex - 3].opcode == .pushInt8, bytecodeArray[endIndex - 3].obj == 1 else {
            return false
        }
        guard bytecodeArray[endIndex - 2].opcode == .add else { return false }
        guard bytecodeArray[endIndex].opcode == .pop, bytecodeArray[endIndex].obj == 3 else { return false }

        return true
    }

    func getVarNameFromSet(_ index: Int) -> String {
        let bytecode = handler.bytecodeArray[index]
        switch bytecode.opcode {
        case .setGlobal, .setGlobal2, .setProp:
            return getName(bytecode.obj)
        case .setParam:
            return getArgumentName(bytecode.obj)
        case .setLocal:
            return getLocalName(bytecode.obj)
        default:
            return "unknown"
        }
    }

    // MARK: - Main decode loop

    func parse() {
        tagLoops()
        stack.removeAll()

        var i = 0
        while i < handler.bytecodeArray.count {
            let pos = UInt32(handler.bytecodeArray[i].pos)

            while pos == currentBlock.endPos {
                if let context = exitBlock() {
                    switch context {
                    case .ifBlock1(let ifNode):
                        if ifNode.hasElse {
                            enterBlock(ifNode.block2, context: .ifBlock2)
                        }
                    case .caseLabel:
                        if let label = currentBlock.currentCaseLabel {
                            switch label.expect {
                            case .otherwise:
                                currentBlock.currentCaseLabel = nil
                                for child in currentBlock.children.reversed() {
                                    if case .caseStatement(let caseNode) = child.node {
                                        let otherwiseNode = OtherwiseNode()
                                        caseNode.otherwise = otherwiseNode
                                        let owPos = caseNode.potentialOtherwisePos
                                        if owPos >= 0, let owIndex = bytecodePosMap[Int(owPos)] {
                                            bytecodeTags[owIndex].tag = .endCase
                                        }
                                        enterBlock(otherwiseNode.block, context: .caseOtherwise)
                                        break
                                    }
                                }
                            case .end:
                                currentBlock.currentCaseLabel = nil
                            default:
                                break
                            }
                        }
                    default:
                        break
                    }
                }
            }

            currentBytecodeIndex = i
            i += translateBytecode(i)
        }
    }

    /// Decodes the instruction at `index`, pushing an expression or adding a
    /// statement to the current block as appropriate, and returns how many
    /// bytecode entries it consumed (almost always 1 — `Peek`'s case-label
    /// lookahead is the one exception).
    @discardableResult
    func translateBytecode(_ index: Int) -> Int {
        let tag = bytecodeTags[index].tag
        if tag == .skip || tag == .nextRepeatTarget {
            return 1
        }

        let bytecode = handler.bytecodeArray[index]
        let opcode = bytecode.opcode
        let obj = bytecode.obj

        var nextBlock: (BlockNode, BlockContext)?
        var collectedIndices: [Int] = [index]
        var translation: AstNode?

        switch opcode {
        case .ret, .retFactory:
            translation = index == handler.bytecodeArray.count - 1 ? nil : .exit

        case .pushZero:
            translation = .literal(.int(0))

        case .mul, .add, .sub, .div, .mod, .joinStr, .joinPadStr,
            .lt, .ltEq, .ntEq, .eq, .gt, .gtEq,
            .and, .or, .containsStr, .contains0Str:
            let b = popWithIndices(&collectedIndices)
            let a = popWithIndices(&collectedIndices)
            translation = .binaryOp(opcode: opcode, left: a, right: b)

        case .inv:
            translation = .inverseOp(popWithIndices(&collectedIndices))

        case .not:
            translation = .notOp(popWithIndices(&collectedIndices))

        case .getChunk:
            let string = popWithIndices(&collectedIndices)
            translation = readChunkRef(string, indices: &collectedIndices)

        case .hiliteChunk:
            let castId: AstNode? = version >= 500 ? popWithIndices(&collectedIndices) : nil
            let fieldId = popWithIndices(&collectedIndices)
            let field: AstNode = .member(memberType: "field", memberID: fieldId, castID: castId)
            translation = .chunkHilite(readChunkRef(field, indices: &collectedIndices))

        case .ontoSpr:
            let second = popWithIndices(&collectedIndices)
            let first = popWithIndices(&collectedIndices)
            translation = .spriteIntersects(first: first, second: second)

        case .intoSpr:
            let second = popWithIndices(&collectedIndices)
            let first = popWithIndices(&collectedIndices)
            translation = .spriteWithin(first: first, second: second)

        case .getField:
            let castId: AstNode? = version >= 500 ? popWithIndices(&collectedIndices) : nil
            let fieldId = popWithIndices(&collectedIndices)
            translation = .member(memberType: "field", memberID: fieldId, castID: castId)

        case .startTell:
            let window = popWithIndices(&collectedIndices)
            let block = BlockNode()
            translation = .tell(window: window, block: block)
            nextBlock = (block, .tell)

        case .endTell:
            exitBlock()
            translation = nil

        case .pushList:
            let list = popWithIndices(&collectedIndices)
            if case .literal(var datum) = list {
                datum.datumType = .list
                translation = .literal(datum)
            } else {
                translation = list
            }

        case .pushPropList:
            let list = popWithIndices(&collectedIndices)
            if case .literal(var datum) = list {
                datum.datumType = .propList
                translation = .literal(datum)
            } else {
                translation = list
            }

        case .swap:
            if stack.count >= 2 {
                stack.swapAt(stack.count - 1, stack.count - 2)
            }
            translation = nil

        case .pushInt8, .pushInt16, .pushInt32:
            translation = .literal(.int(Int32(truncatingIfNeeded: obj)))

        case .pushFloat32:
            let bits = UInt32(truncatingIfNeeded: obj)
            translation = .literal(.float(Double(Float(bitPattern: bits))))

        case .pushArgListNoRet:
            var args: [AstNode] = []
            for _ in 0..<Int(obj) {
                args.append(popWithIndices(&collectedIndices))
            }
            translation = .literal(.argListNoRet(args.reversed()))

        case .pushArgList:
            var args: [AstNode] = []
            for _ in 0..<Int(obj) {
                args.append(popWithIndices(&collectedIndices))
            }
            translation = .literal(.argList(args.reversed()))

        case .pushCons:
            let literalId = Int(UInt32(truncatingIfNeeded: obj) / multiplier)
            if let literal = chunk.literals[safe: literalId] {
                let datum: Datum
                switch literal {
                case .string(let s): datum = .string(s)
                case .int(let value): datum = .int(value)
                case .double(let f): datum = .float(f)
                case .invalid, .javascript: datum = .void()
                }
                translation = .literal(datum)
            } else {
                translation = .error
            }

        case .pushSymb:
            translation = .literal(.symbol(getName(obj)))

        case .pushVarRef:
            translation = .literal(.varRef(getName(obj)))

        case .getGlobal, .getGlobal2, .getProp:
            translation = .variable(getName(obj))

        case .getParam:
            translation = .variable(getArgumentName(obj))

        case .getLocal:
            translation = .variable(getLocalName(obj))

        case .setGlobal, .setGlobal2, .setProp:
            let value = popWithIndices(&collectedIndices)
            translation = .assignment(variable: .variable(getName(obj)), value: value, forceVerbose: false)

        case .setParam:
            let value = popWithIndices(&collectedIndices)
            translation = .assignment(
                variable: .variable(getArgumentName(obj)), value: value, forceVerbose: false)

        case .setLocal:
            let value = popWithIndices(&collectedIndices)
            translation = .assignment(
                variable: .variable(getLocalName(obj)), value: value, forceVerbose: false)

        case .jmp:
            translation = translateJmp(index: index, obj: obj, nextBlock: &nextBlock)

        case .endRepeat:
            translation = .comment("ERROR: Stray endrepeat")

        case .jmpIfZ:
            translation = translateJmpIfZ(
                index: index, obj: obj, nextBlock: &nextBlock, indices: &collectedIndices)

        case .localCall:
            let argList = popWithIndices(&collectedIndices)
            let handlerName: String
            if let handlerDef = chunk.handlers[safe: Int(obj)] {
                handlerName = names[safe: Int(handlerDef.nameId)] ?? "handler_\(obj)"
            } else {
                handlerName = "handler_\(obj)"
            }
            translation = .call(name: handlerName, args: argList)

        case .extCall, .tellCall:
            let name = getName(obj)
            let argList = popWithIndices(&collectedIndices)
            translation = .call(name: name, args: argList)

        case .objCallV4:
            let argList = popWithIndices(&collectedIndices)
            let object = readVar(obj, indices: &collectedIndices)
            translation = .objCallV4(obj: object, args: argList)

        case .put:
            let putType = Self.putType(from: obj)
            let variable = readVar(obj & 0xF, indices: &collectedIndices)
            let value = popWithIndices(&collectedIndices)
            translation = .put(putType: putType, variable: variable, value: value)

        case .putChunk:
            let putType = Self.putType(from: obj)
            let variable = readVar(obj & 0xF, indices: &collectedIndices)
            let chunkRef = readChunkRef(variable, indices: &collectedIndices)
            let value = popWithIndices(&collectedIndices)
            translation = .put(putType: putType, variable: chunkRef, value: value)

        case .deleteChunk:
            let variable = readVar(obj, indices: &collectedIndices)
            translation = .chunkDelete(readChunkRef(variable, indices: &collectedIndices))

        case .get:
            let propId = popWithIndices(&collectedIndices)
            translation = readV4Property(propertyType: obj, propertyID: propId.value?.toInt() ?? 0)

        case .set:
            let propId = popWithIndices(&collectedIndices)
            let value = popWithIndices(&collectedIndices)
            if let prop = readV4Property(propertyType: obj, propertyID: propId.value?.toInt() ?? 0) {
                translation = .assignment(variable: prop, value: value, forceVerbose: true)
            } else {
                translation = .error
            }

        case .getMovieProp:
            translation = .the(getName(obj))

        case .setMovieProp:
            let value = popWithIndices(&collectedIndices)
            translation = .assignment(variable: .the(getName(obj)), value: value, forceVerbose: false)

        case .getObjProp, .getChainedProp:
            let object = popWithIndices(&collectedIndices)
            translation = .objProp(obj: object, prop: getName(obj))

        case .setObjProp:
            let value = popWithIndices(&collectedIndices)
            let object = popWithIndices(&collectedIndices)
            translation = .assignment(
                variable: .objProp(obj: object, prop: getName(obj)), value: value, forceVerbose: false)

        case .peek:
            return translatePeek(index)

        case .pop:
            if bytecodeTags[index].tag == .endCase {
                return 1
            }
            if obj == 1 && stack.count == 1 {
                let value = popWithIndices(&collectedIndices)
                translation = .caseStatement(CaseNode(value: value))
            } else {
                return 1
            }

        case .theBuiltin:
            _ = popWithIndices(&collectedIndices)  // empty arglist
            translation = .the(getName(obj))

        case .objCall:
            let method = getName(obj)
            let argList = popWithIndices(&collectedIndices)
            translation = translateObjCall(method: method, argList: argList)

        case .pushChunkVarRef:
            translation = readVar(obj, indices: &collectedIndices)

        case .getTopLevelProp:
            translation = .variable(getName(obj))

        case .newObj:
            let objArgs = popWithIndices(&collectedIndices)
            translation = .newObj(objType: getName(obj), args: objArgs)

        default:
            let opID = opcode.rawValue
            translation = .comment(
                opID > 0x40
                    ? "Unknown opcode \(String(format: "%02x", opID)) \(obj)"
                    : "Unknown opcode \(String(format: "%02x", opID))")
            stack.removeAll()
        }

        if let node = translation {
            if node.isExpression {
                push(node, indices: collectedIndices)
            } else {
                addStatement(node, bytecodeIndices: collectedIndices)
            }
        }

        if let (block, context) = nextBlock {
            enterBlock(block, context: context)
        }

        return 1
    }

    /// `Put`/`PutChunk`'s operand packs both the put type and the variable
    /// kind into one byte: high nibble selects into/after/before, low
    /// nibble is the variable-kind tag `readVar` expects.
    private static func putType(from obj: Int64) -> PutType {
        switch (obj >> 4) & 0xF {
        case 1: return .into
        case 2: return .after
        case 3: return .before
        default: return .into
        }
    }

    func translateJmp(index: Int, obj: Int64, nextBlock: inout (BlockNode, BlockContext)?) -> AstNode? {
        let bytecodeArray = handler.bytecodeArray
        let bytecode = bytecodeArray[index]
        let targetPos = bytecode.pos + Int(obj)

        guard let targetIndex = bytecodePosMap[targetPos] else {
            return .comment("ERROR: Invalid jump target")
        }

        if let ancestorLoopStart = ancestorLoopStartIndex() {
            if targetIndex > 0 {
                let prevBytecode = bytecodeArray[targetIndex - 1]
                if prevBytecode.opcode == .endRepeat,
                    bytecodeTags[targetIndex - 1].ownerLoop == ancestorLoopStart
                {
                    return .exitRepeat
                }
            }
            if bytecodeTags[targetIndex].tag == .nextRepeatTarget,
                bytecodeTags[targetIndex].ownerLoop == ancestorLoopStart
            {
                return .nextRepeat
            }
        }

        // A jump landing right where the current block ends is either an
        // `if`'s jump-past-the-else-branch, or a `case` label's jump past
        // the whole statement.
        if index + 1 < bytecodeArray.count {
            let nextBytecode = bytecodeArray[index + 1]
            if UInt32(nextBytecode.pos) == currentBlock.endPos, let ctx = ancestorStatementContext() {
                switch ctx {
                case .ifBlock1(let ifNode):
                    ifNode.hasElse = true
                    ifNode.block2.endPos = UInt32(targetPos)
                    return nil
                case .caseLabel:
                    if blockStack.count >= 2 {
                        let grandparent = blockStack[blockStack.count - 2]
                        for child in grandparent.children.reversed() {
                            if case .caseStatement(let caseNode) = child.node {
                                caseNode.potentialOtherwisePos = Int32(bytecode.pos)
                                caseNode.endPos = Int32(targetPos)
                                bytecodeTags[targetIndex].tag = .endCase
                                return nil
                            }
                        }
                    }
                    return nil
                default:
                    break
                }
            }
        }

        // A jump forward to a `Pop 1` marks a `case` statement whose first
        // label is `otherwise` (no regular labels at all).
        if targetIndex < bytecodeArray.count {
            let targetBytecode = bytecodeArray[targetIndex]
            if targetBytecode.opcode == .pop, targetBytecode.obj == 1 {
                let value = pop()
                let caseNode = CaseNode(value: value, endPos: Int32(targetPos))
                bytecodeTags[targetIndex].tag = .endCase
                let otherwiseNode = OtherwiseNode()
                caseNode.otherwise = otherwiseNode
                nextBlock = (otherwiseNode.block, .caseOtherwise)
                return .caseStatement(caseNode)
            }
        }

        return .comment("ERROR: Could not identify jmp")
    }

    func translateJmpIfZ(
        index: Int, obj: Int64, nextBlock: inout (BlockNode, BlockContext)?, indices: inout [Int]
    ) -> AstNode? {
        let bytecode = handler.bytecodeArray[index]
        let endPos = UInt32(truncatingIfNeeded: Int64(bytecode.pos) + obj)
        let tag = bytecodeTags[index].tag

        switch tag {
        case .repeatWhile:
            let condition = popWithIndices(&indices)
            let block = BlockNode()
            block.endPos = endPos
            nextBlock = (block, .loop(startIndex: UInt32(index)))
            return .repeatWhile(condition: condition, block: block, startIndex: UInt32(index))

        case .repeatWithIn:
            let list = popWithIndices(&indices)
            let varName = getVarNameFromSet(index + 5)
            let block = BlockNode()
            block.endPos = endPos
            nextBlock = (block, .loop(startIndex: UInt32(index)))
            return .repeatWithIn(varName: varName, list: list, block: block, startIndex: UInt32(index))

        case .repeatWithTo, .repeatWithDownTo:
            let up = tag == .repeatWithTo
            let end = popWithIndices(&indices)
            let start = popWithIndices(&indices)

            let bytecodeArray = handler.bytecodeArray
            let endIndex = bytecodePosMap[Int(endPos)] ?? index
            let endRepeat = bytecodeArray[max(0, endIndex - 1)]
            let conditionStartPos = max(0, endRepeat.pos - Int(endRepeat.obj))
            let conditionStartIndex = bytecodePosMap[conditionStartPos] ?? 0
            let varName = conditionStartIndex > 0 ? getVarNameFromSet(conditionStartIndex - 1) : "i"

            let block = BlockNode()
            block.endPos = endPos
            nextBlock = (block, .loop(startIndex: UInt32(index)))
            return .repeatWithTo(
                varName: varName, start: start, end: end, up: up, block: block, startIndex: UInt32(index))

        default:
            let condition = popWithIndices(&indices)
            let block1 = BlockNode()
            block1.endPos = endPos
            let block2 = BlockNode()
            let ifNode = IfNode(condition: condition, block1: block1, block2: block2)
            nextBlock = (block1, .ifBlock1(ifNode))
            return .ifStatement(ifNode)
        }
    }

    /// Handles `Peek`, which only ever appears as part of a `case` statement:
    /// it duplicates the case value on the stack so it can be compared
    /// against each label in turn. This recursively decodes bytecodes after
    /// the peek until it finds the `eq`/`nteq` comparison that closes out one
    /// label, classifying what follows (another label, `otherwise`, or the
    /// end of the statement) from the shape of the jump after it.
    func translatePeek(_ index: Int) -> Int {
        let prevLabel = currentBlock.currentCaseLabel
        let originalStackSize = stack.count

        var currIndex = index + 1
        while currIndex < handler.bytecodeArray.count {
            currentBytecodeIndex = currIndex
            currIndex += translateBytecode(currIndex)
            if currIndex < handler.bytecodeArray.count {
                let nextBC = handler.bytecodeArray[currIndex]
                if stack.count == originalStackSize + 1, nextBC.opcode == .eq || nextBC.opcode == .ntEq {
                    break
                }
            }
        }

        if currIndex >= handler.bytecodeArray.count {
            addStatement(.comment("ERROR: Expected eq or nteq!"), bytecodeIndices: [index])
            return currIndex - index + 1
        }

        let notEq = handler.bytecodeArray[currIndex].opcode == .ntEq
        let caseValue = pop()

        currIndex += 1
        if currIndex >= handler.bytecodeArray.count || handler.bytecodeArray[currIndex].opcode != .jmpIfZ {
            addStatement(.comment("ERROR: Expected jmpifz!"), bytecodeIndices: [index])
            return currIndex - index + 1
        }

        let jmpifz = handler.bytecodeArray[currIndex]
        let jmpPos = Int(Int64(jmpifz.pos) + jmpifz.obj)
        let targetIndex = bytecodePosMap[jmpPos] ?? 0

        let expect: CaseExpect
        if notEq {
            expect = .or
        } else if targetIndex < handler.bytecodeArray.count, handler.bytecodeArray[targetIndex].opcode == .peek {
            expect = .next
        } else if targetIndex < handler.bytecodeArray.count,
            handler.bytecodeArray[targetIndex].opcode == .pop,
            handler.bytecodeArray[targetIndex].obj == 1,
            targetIndex == 0
                || handler.bytecodeArray[targetIndex - 1].opcode != .jmp
                || (Int64(handler.bytecodeArray[targetIndex - 1].pos)
                    + handler.bytecodeArray[targetIndex - 1]
                    .obj) == Int64(handler.bytecodeArray[targetIndex].pos)
        {
            expect = .end
        } else {
            expect = .otherwise
        }

        let currLabel = CaseLabelNode(value: caseValue, expect: expect)
        currentBlock.currentCaseLabel = currLabel

        if let prev = prevLabel {
            if prev.expect == .or {
                prev.nextOr = currLabel
            } else if prev.expect == .next {
                prev.nextLabel = currLabel
            }
        } else {
            let peekedValue = pop()
            let caseNode = CaseNode(value: peekedValue, firstLabel: currLabel)
            addStatement(.caseStatement(caseNode), bytecodeIndices: [index])
        }

        if expect != .or {
            let block = BlockNode()
            block.endPos = UInt32(jmpPos)
            currLabel.block = block
            enterBlock(block, context: .caseLabel)
        }

        return currIndex - index + 1
    }

    /// `ObjCall` covers Director's built-in list/string/object methods.
    /// Several of them (`getAt`, `setAt`, `getProp`, ...) have dedicated,
    /// more idiomatic `AstNode` shapes (bracket indexing, property
    /// assignment, ...) that read better than a generic method call, so
    /// this recognizes those by name/arity before falling back to a plain
    /// `objCall`.
    func translateObjCall(method: String, argList: AstNode) -> AstNode? {
        if case .literal(let datum) = argList {
            let args = datum.listValue
            let nargs = args.count

            switch method {
            case "getAt" where nargs == 2:
                return .objBracket(obj: args[0], prop: args[1])
            case "setAt" where nargs == 3:
                let propExpr: AstNode = .objBracket(obj: args[0], prop: args[1])
                return .assignment(variable: propExpr, value: args[2], forceVerbose: false)
            case "hilite" where nargs == 1:
                return .chunkHilite(args[0])
            case "delete" where nargs == 1:
                return .chunkDelete(args[0])
            case "getProp",
                "getPropRef" where nargs == 3 || nargs == 4:
                if let datum = args[1].value, datum.datumType == .symbol {
                    let i2: AstNode? = nargs == 4 ? args[3] : nil
                    return .objPropIndex(
                        obj: args[0], prop: datum.stringValue, index: args[2], index2: i2)
                }
            case "setProp" where nargs == 4 || nargs == 5:
                if let datum = args[1].value, datum.datumType == .symbol {
                    let i2: AstNode? = nargs == 5 ? args[3] : nil
                    let propExpr: AstNode = .objPropIndex(
                        obj: args[0], prop: datum.stringValue, index: args[2], index2: i2)
                    return .assignment(variable: propExpr, value: args[nargs - 1], forceVerbose: false)
                }
            case "count" where nargs == 2:
                if let datum = args[1].value, datum.datumType == .symbol {
                    let propExpr: AstNode = .objProp(obj: args[0], prop: datum.stringValue)
                    return .objProp(obj: propExpr, prop: "count")
                }
            case "setContents", "setContentsAfter",
                "setContentsBefore" where nargs == 2:
                let putType: PutType = method == "setContents" ? .into : (method == "setContentsAfter" ? .after : .before)
                return .put(putType: putType, variable: args[0], value: args[1])
            default:
                break
            }
        }
        return .objCall(name: method, args: argList)
    }

    /// Resolves a variable reference of the given `varType` (global/property,
    /// argument, local, or field) into the appropriate `AstNode`, popping the
    /// stack for whichever operands that variable kind needs (an id, plus a
    /// cast-library id for fields in Director 5+).
    func readVar(_ varType: Int64, indices: inout [Int]) -> AstNode {
        let castId: AstNode? = (varType == 0x6 && version >= 500) ? popWithIndices(&indices) : nil
        let id = popWithIndices(&indices)

        switch varType {
        case 0x1, 0x2, 0x3:
            return id
        case 0x4:
            if let datum = id.value {
                return .literal(.varRef(getArgumentName(Int64(datum.toInt()))))
            }
            return id
        case 0x5:
            if let datum = id.value {
                return .literal(.varRef(getLocalName(Int64(datum.toInt()))))
            }
            return id
        case 0x6:
            return .member(memberType: "field", memberID: id, castID: castId)
        default:
            return .error
        }
    }

    /// Reads the (up to) four chunk-range pairs (char/word/item/line, each a
    /// first/last index) that Director always pushes before a chunk-typed
    /// string expression, wrapping `string` from the innermost (char) to
    /// outermost (line) chunk type for whichever ranges are actually
    /// non-zero.
    func readChunkRef(_ string: AstNode, indices: inout [Int]) -> AstNode {
        let lastLine = popWithIndices(&indices)
        let firstLine = popWithIndices(&indices)
        let lastItem = popWithIndices(&indices)
        let firstItem = popWithIndices(&indices)
        let lastWord = popWithIndices(&indices)
        let firstWord = popWithIndices(&indices)
        let lastChar = popWithIndices(&indices)
        let firstChar = popWithIndices(&indices)

        var result = string

        if !isZero(firstLine) {
            result = .chunkExpr(chunkType: .line, first: firstLine, last: lastLine, string: result)
        }
        if !isZero(firstItem) {
            result = .chunkExpr(chunkType: .item, first: firstItem, last: lastItem, string: result)
        }
        if !isZero(firstWord) {
            result = .chunkExpr(chunkType: .word, first: firstWord, last: lastWord, string: result)
        }
        if !isZero(firstChar) {
            result = .chunkExpr(chunkType: .char, first: firstChar, last: lastChar, string: result)
        }

        return result
    }

    /// Director 4's `Get`/`Set` opcodes address "the property of object"
    /// through one flat, versioned numbering scheme (movie properties, chunk
    /// counts, menu/sound/sprite properties, member properties, ...) rather
    /// than the named-property opcodes later versions use.
    func readV4Property(propertyType: Int64, propertyID: Int32) -> AstNode? {
        switch propertyType {
        case 0x00:
            if propertyID <= 0x0b {
                return .the(PropertyNames.movieProperty(propertyID))
            }
            let string = pop()
            let chunkType = Self.v4ChunkType(propertyID - 0x0b)
            return .lastStringChunk(chunkType: chunkType, obj: string)

        case 0x01:
            let string = pop()
            return .stringChunkCount(chunkType: Self.v4ChunkType(propertyID), obj: string)

        case 0x02:
            return .menuProp(menuID: pop(), prop: UInt32(bitPattern: propertyID))

        case 0x03:
            let menuId = pop()
            let itemId = pop()
            return .menuItemProp(menuID: menuId, itemID: itemId, prop: UInt32(bitPattern: propertyID))

        case 0x04:
            return .soundProp(soundID: pop(), prop: UInt32(bitPattern: propertyID))

        case 0x05:
            return .comment("ERROR: Resource property")

        case 0x06:
            return .spriteProp(spriteID: pop(), prop: UInt32(bitPattern: propertyID))

        case 0x07:
            return .the(PropertyNames.animationProperty(propertyID))

        case 0x08:
            let propName = PropertyNames.animation2Property(propertyID)
            if propertyID == 0x02, version >= 500 {
                let castLib = pop()
                let isZero: Bool
                if case .literal(let d) = castLib {
                    isZero = d.datumType == .int && d.intValue == 0
                } else {
                    isZero = false
                }
                if !isZero {
                    let castLibNode: AstNode = .member(memberType: "castLib", memberID: castLib, castID: nil)
                    return .theProp(obj: castLibNode, prop: propName)
                }
            }
            return .the(propName)

        case 0x09...0x15:
            let propName = PropertyNames.memberProperty(propertyID)
            let castId: AstNode? = version >= 500 ? pop() : nil
            let memberId = pop()
            let prefix: String
            if propertyType == 0x0b || propertyType == 0x0c {
                prefix = "field"
            } else if propertyType == 0x14 || propertyType == 0x15 {
                prefix = "script"
            } else if version >= 500 {
                prefix = "member"
            } else {
                prefix = "cast"
            }
            let member: AstNode = .member(memberType: prefix, memberID: memberId, castID: castId)
            var scratch: [Int] = []
            let entity =
                (propertyType == 0x0a || propertyType == 0x0c || propertyType == 0x15)
                ? readChunkRef(member, indices: &scratch) : member
            return .theProp(obj: entity, prop: propName)

        default:
            return .comment("ERROR: Unknown property type \(propertyType)")
        }
    }

    private static func v4ChunkType(_ id: Int32) -> ChunkExprType {
        switch id {
        case 1: return .char
        case 2: return .word
        case 3: return .item
        case 4: return .line
        default: return .char
        }
    }
}

/// A per-index bytecode tag produced by `DecompilerState.tagLoops()`.
/// `ownerLoop` is only meaningful when `tag` is `.nextRepeatTarget`: it
/// records which loop's `JmpIfZ` index this instruction belongs to, so a
/// backward jump can be matched to the loop it's exiting/continuing.
struct BytecodeInfo: Equatable {
    var tag: BytecodeTag = .none
    var ownerLoop: UInt32 = 0
}

/// One entry on the decompiler's expression stack.
struct StackEntry {
    var node: AstNode
    var bytecodeIndices: [Int]
}

/// Tracks what kind of statement owns the block currently being decoded, so
/// that reaching its end position can trigger the right follow-up (entering
/// an `if`'s else branch, recognizing a `case` statement's `otherwise`, ...).
enum BlockContext {
    case root
    case ifBlock1(IfNode)
    case ifBlock2
    case caseLabel
    case caseOtherwise
    case loop(startIndex: UInt32)
    case tell
}

private func isZero(_ node: AstNode) -> Bool {
    if case .literal(let datum) = node {
        return datum.datumType == .int && datum.intValue == 0
    }
    return false
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
