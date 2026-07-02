import LingoAST

/// Converts the decompiler's intermediate tree into `LingoAST`'s public
/// `Statement`/`Expression` types — the one step with no direct source
/// analogue, since the intermediate tree's structure already mirrors
/// `LingoAST`'s shape closely enough that most cases are a 1:1 rename.
///
/// `syntax` (`.dot` vs `.verbose`) is threaded through every recursive call
/// the same way Director itself picks a rendering dialect by file version:
/// Director 5+ movies use the object-oriented `.dot` syntax, earlier ones use
/// `.verbose`. `theProp` is the one exception — Director always renders
/// "the property of object" in verbose form even in `.dot`-syntax movies, so
/// it hardcodes `.verbose` regardless of the ambient syntax.
extension BlockNode {
    func asStatements(syntax: LingoSyntax) -> [Statement] {
        children.map { $0.node.asStatement(syntax: syntax) }
    }
}

extension Datum {
    func asExpression(syntax: LingoSyntax) -> Expression {
        switch datumType {
        case .void: return .void
        case .int: return .integer(Int(intValue))
        case .float: return .float(floatValue)
        case .string: return .string(stringValue)
        case .symbol: return .symbol(stringValue)
        case .varRef: return .identifier(stringValue)
        case .list: return .list(listValue.map { $0.asExpression(syntax: syntax) })
        case .argList: return .argList(listValue.map { $0.asExpression(syntax: syntax) })
        case .argListNoRet: return .argListNoRet(listValue.map { $0.asExpression(syntax: syntax) })
        case .propList:
            var entries: [PropertyListEntry] = []
            var i = 0
            while i + 1 < listValue.count {
                entries.append(
                    PropertyListEntry(
                        key: listValue[i].asExpression(syntax: syntax),
                        value: listValue[i + 1].asExpression(syntax: syntax)))
                i += 2
            }
            return .propertyList(entries)
        }
    }
}

extension ChunkExprType {
    fileprivate var lingoASTChunkType: ChunkType {
        switch self {
        case .char: return .char
        case .word: return .word
        case .item: return .item
        case .line: return .line
        }
    }
}

extension AstNode {
    func asExpression(syntax: LingoSyntax) -> Expression {
        switch self {
        case .error:
            return .identifier("ERROR")

        case .literal(let datum):
            return datum.asExpression(syntax: syntax)

        case .variable(let name):
            return .identifier(name)

        case .binaryOp(let opcode, let left, let right):
            return .binaryOperation(
                left: left.asExpression(syntax: syntax),
                operator: binaryOperator(for: opcode),
                right: right.asExpression(syntax: syntax))

        case .inverseOp(let operand):
            return .unaryOperation(operator: .negate, operand: operand.asExpression(syntax: syntax))

        case .notOp(let operand):
            return .unaryOperation(operator: .not, operand: operand.asExpression(syntax: syntax))

        case .chunkExpr(let chunkType, let first, let last, let string):
            return chunkExpression(
                chunkType: chunkType, first: first, last: last, string: string, syntax: syntax)

        case .spriteIntersects(let first, let second):
            return .spriteIntersects(
                first: first.asExpression(syntax: syntax), second: second.asExpression(syntax: syntax))

        case .spriteWithin(let first, let second):
            return .spriteWithin(
                first: first.asExpression(syntax: syntax), second: second.asExpression(syntax: syntax))

        case .member(let memberType, let memberID, let castID):
            return .member(
                type: memberType, id: memberID.asExpression(syntax: syntax),
                castId: castID?.asExpression(syntax: syntax))

        case .the(let prop):
            return .the(prop)

        case .theProp(let obj, let prop):
            // Always verbose — see the file-level note.
            return .propertyAccess(target: obj.asExpression(syntax: syntax), property: prop, syntax: .verbose)

        case .objProp(let obj, let prop):
            return .propertyAccess(target: obj.asExpression(syntax: syntax), property: prop, syntax: syntax)

        case .objBracket(let obj, let prop):
            return .elementAccess(
                target: obj.asExpression(syntax: syntax), index: prop.asExpression(syntax: syntax))

        case .objPropIndex(let obj, let prop, let index, let index2):
            return .objPropIndex(
                obj: obj.asExpression(syntax: syntax), prop: prop,
                index: index.asExpression(syntax: syntax),
                index2: index2?.asExpression(syntax: syntax))

        case .lastStringChunk(let chunkType, let obj):
            return .lastStringChunk(
                type: chunkType.lingoASTChunkType, obj: obj.asExpression(syntax: syntax))

        case .stringChunkCount(let chunkType, let obj):
            return .stringChunkCount(
                type: chunkType.lingoASTChunkType, obj: obj.asExpression(syntax: syntax))

        case .menuProp(let menuID, let prop):
            return .menuProp(menuId: menuID.asExpression(syntax: syntax), prop: menuPropName(prop))

        case .menuItemProp(let menuID, let itemID, let prop):
            return .menuItemProp(
                menuId: menuID.asExpression(syntax: syntax), itemId: itemID.asExpression(syntax: syntax),
                prop: menuItemPropName(prop))

        case .soundProp(let soundID, let prop):
            return .soundProp(soundId: soundID.asExpression(syntax: syntax), prop: soundPropName(prop))

        case .spriteProp(let spriteID, let prop):
            return .spriteProp(spriteId: spriteID.asExpression(syntax: syntax), prop: spritePropName(prop))

        case .call(let name, let args):
            return .call(name: name, args: args.asExpression(syntax: syntax))

        case .objCall(let name, let args):
            return .objCall(name: name, args: args.asExpression(syntax: syntax))

        case .objCallV4(let obj, let args):
            return .objCallV4(obj: obj.asExpression(syntax: syntax), args: args.asExpression(syntax: syntax))

        case .newObj(let objType, let args):
            return .newObj(type: objType, args: args.asExpression(syntax: syntax))

        // Every other case is statement-shaped and, by construction, never
        // ends up nested inside an expression: `DecompilerState` routes them
        // straight to `addStatement`, never onto the expression stack that
        // feeds another node's fields. Fall back to `.void` rather than
        // crash if that invariant is ever violated by a bytecode shape this
        // port doesn't yet recognize.
        case .comment, .block, .assignment, .chunkHilite, .chunkDelete, .exit, .exitRepeat, .nextRepeat,
            .put, .ifStatement, .repeatWhile, .repeatWithIn, .repeatWithTo, .tell, .caseStatement, .when,
            .soundCmd, .playCmd:
            return .void
        }
    }

    func asStatement(syntax: LingoSyntax) -> Statement {
        switch self {
        case .assignment(let variable, let value, let forceVerbose):
            return .assignment(
                target: variable.asExpression(syntax: syntax),
                value: value.asExpression(syntax: syntax),
                syntax: forceVerbose ? .verbose : syntax)

        case .chunkHilite(let chunk):
            return .chunkHilite(chunk: chunk.asExpression(syntax: syntax))

        case .chunkDelete(let chunk):
            return .chunkDelete(chunk: chunk.asExpression(syntax: syntax))

        case .exit:
            return .exit

        case .exitRepeat:
            return .exitRepeat

        case .nextRepeat:
            return .nextRepeat

        case .put(let putType, let variable, let value):
            return .put(
                type: putType, value: value.asExpression(syntax: syntax),
                target: variable.asExpression(syntax: syntax))

        case .ifStatement(let ifNode):
            let elseBody =
                (ifNode.hasElse && !ifNode.block2.children.isEmpty)
                ? ifNode.block2.asStatements(syntax: syntax) : nil
            return .ifStatement(
                condition: ifNode.condition.asExpression(syntax: syntax),
                body: ifNode.block1.asStatements(syntax: syntax),
                elseBody: elseBody)

        case .repeatWhile(let condition, let block, _):
            return .repeatWhile(
                condition: condition.asExpression(syntax: syntax), body: block.asStatements(syntax: syntax))

        case .repeatWithIn(let varName, let list, let block, _):
            return .repeatWithIn(
                variable: varName, list: list.asExpression(syntax: syntax),
                body: block.asStatements(syntax: syntax))

        case .repeatWithTo(let varName, let start, let end, let up, let block, _):
            return .repeatWithCounter(
                variable: varName, start: start.asExpression(syntax: syntax),
                end: end.asExpression(syntax: syntax), body: block.asStatements(syntax: syntax), up: up)

        case .tell(let window, let block):
            return .tell(window: window.asExpression(syntax: syntax), body: block.asStatements(syntax: syntax))

        case .caseStatement(let caseNode):
            return .caseStatement(
                condition: caseNode.value.asExpression(syntax: syntax),
                cases: caseBlocks(from: caseNode.firstLabel, syntax: syntax),
                otherwise: caseNode.otherwise.map { $0.block.asStatements(syntax: syntax) })

        case .when(let event, let script):
            return .when(event: eventName(event), script: script)

        case .soundCmd(let cmd, let args):
            return .soundCmd(cmd: cmd, args: args.asExpression(syntax: syntax))

        case .playCmd(let args):
            return .playCmd(args: args.asExpression(syntax: syntax))

        case .comment(let text):
            // Decompiled comments carry diagnostic text (e.g. an
            // unrecognized opcode); there's no dedicated comment statement
            // in `LingoAST`, so surface the message as an inert expression
            // statement rather than drop it silently.
            return .expressionStatement(.string(text))

        // Every other case is expression-shaped; wrap it as a bare
        // expression statement (mirrors a call made for its side effect,
        // e.g. `beep()`).
        default:
            return .expressionStatement(asExpression(syntax: syntax))
        }
    }
}

/// A "chunk 1 of x" single-position reference and a "chunk 1 to 3 of x"
/// range both parse to the same `first`/`last` shape (Director always pushes
/// both), so a single index is only recognizable by `first == last`.
private func chunkExpression(
    chunkType: ChunkExprType, first: AstNode, last: AstNode, string: AstNode, syntax: LingoSyntax
) -> Expression {
    let isSingle: Bool
    if case .literal(let firstDatum) = first, case .literal(let lastDatum) = last {
        isSingle =
            firstDatum.datumType == .int && lastDatum.datumType == .int
            && firstDatum.intValue == lastDatum.intValue
    } else {
        isSingle = false
    }
    return .chunkExpression(
        type: chunkType.lingoASTChunkType,
        first: first.asExpression(syntax: syntax),
        last: isSingle ? nil : last.asExpression(syntax: syntax),
        string: string.asExpression(syntax: syntax),
        syntax: syntax)
}

private func caseBlocks(from firstLabel: CaseLabelNode?, syntax: LingoSyntax) -> [CaseBlock] {
    var blocks: [CaseBlock] = []
    var currentLabel = firstLabel
    while let label = currentLabel {
        var values = [label.value.asExpression(syntax: syntax)]
        var orLabel = label.nextOr
        while let or = orLabel {
            values.append(or.value.asExpression(syntax: syntax))
            orLabel = or.nextOr
        }
        blocks.append(CaseBlock(values: values, body: label.block.asStatements(syntax: syntax)))
        currentLabel = label.nextLabel
    }
    return blocks
}

private func binaryOperator(for opcode: OpCode) -> BinaryOperator {
    switch opcode {
    case .mul: return .multiply
    case .add: return .add
    case .sub: return .subtract
    case .div: return .divide
    case .mod: return .modulo
    case .joinStr: return .stringConcat
    case .joinPadStr: return .stringConcatSpace
    case .lt: return .lessThan
    case .ltEq: return .lessThanOrEqual
    case .ntEq: return .notEquals
    case .eq: return .equals
    case .gt: return .greaterThan
    case .gtEq: return .greaterThanOrEqual
    case .and: return .logicalAnd
    case .or: return .logicalOr
    case .containsStr, .contains0Str: return .contains
    default: return .equals  // unreachable: DecompilerState only builds .binaryOp with the opcodes above
    }
}

private func menuPropName(_ prop: UInt32) -> String {
    switch prop {
    case 0x01: return "name"
    case 0x02: return "number"
    default: return "menuProp_\(prop)"
    }
}

private func menuItemPropName(_ prop: UInt32) -> String {
    switch prop {
    case 0x01: return "name"
    case 0x02: return "checkMark"
    case 0x03: return "enabled"
    case 0x04: return "script"
    default: return "menuItemProp_\(prop)"
    }
}

private func soundPropName(_ prop: UInt32) -> String {
    switch prop {
    case 0x01: return "volume"
    default: return "soundProp_\(prop)"
    }
}

private func spritePropName(_ prop: UInt32) -> String {
    switch prop {
    case 0x01: return "type"
    case 0x02: return "backColor"
    case 0x03: return "bottom"
    case 0x04: return "castNum"
    case 0x05: return "constraint"
    case 0x06: return "cursor"
    case 0x07: return "foreColor"
    case 0x08: return "height"
    case 0x09: return "immediate"
    case 0x0a: return "ink"
    case 0x0b: return "left"
    case 0x0c: return "lineSize"
    case 0x0d: return "locH"
    case 0x0e: return "locV"
    case 0x0f: return "moveableSprite"
    case 0x10: return "pattern"
    case 0x11: return "puppet"
    case 0x12: return "right"
    case 0x13: return "scriptNum"
    case 0x14: return "stretch"
    case 0x15: return "top"
    case 0x16: return "trails"
    case 0x17: return "visible"
    case 0x18: return "width"
    case 0x19: return "blend"
    case 0x1a: return "scriptInstanceList"
    case 0x1b: return "loc"
    case 0x1c: return "rect"
    case 0x1d: return "member"
    default: return "spriteProp_\(prop)"
    }
}

private func eventName(_ event: Int32) -> String {
    switch event {
    case 1: return "mouseDown"
    case 2: return "mouseUp"
    case 3: return "keyDown"
    case 4: return "keyUp"
    case 5: return "timeout"
    default: return "event_\(event)"
    }
}
