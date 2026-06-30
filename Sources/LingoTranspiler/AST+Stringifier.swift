import LingoAST

extension Statement {
    public var lingoString: String {
        switch self {
        case .global(let names): return "global " + names.joined(separator: ", ")
        case .property(let names): return "property " + names.joined(separator: ", ")
        case .handler(let name, let args, _): return "on \(name) " + args.joined(separator: ", ")
        case .assignment(let target, let value): return "\(target.lingoString) = \(value.lingoString)"
        case .put(let type, let value, let target):
            let targetStr = target != nil ? " \(type) \(target!.lingoString)" : ""
            return "put \(value.lingoString)\(targetStr)"
        case .ifStatement(let cond, _, _): return "if \(cond.lingoString) then"
        case .repeatWithCounter(let variable, let start, let end, _, let up):
            let dir = up ? "to" : "down to"
            return "repeat with \(variable) = \(start.lingoString) \(dir) \(end.lingoString)"
        case .repeatWhile(let cond, _): return "repeat while \(cond.lingoString)"
        case .repeatWithIn(let variable, let list, _): return "repeat with \(variable) in \(list.lingoString)"
        case .expressionStatement(let expr): return expr.lingoString
        case .returnStatement(let expr):
            return expr != nil ? "return \(expr!.lingoString)" : "return"
        case .exit: return "exit"
        case .exitRepeat: return "exit repeat"
        case .nextRepeat: return "next repeat"
        case .caseStatement(let cond, _, _): return "case \(cond.lingoString) of"
        case .tell(let window, _): return "tell \(window.lingoString)"
        case .when(let event, let script): return "when \(event) then \(script)"
        case .soundCmd(let cmd, let args):
            return args != nil ? "\(cmd) \(args!.lingoString)" : cmd
        case .playCmd(let args):
            return args != nil ? "play \(args!.lingoString)" : "play"
        case .chunkHilite(let chunk): return "hilite \(chunk.lingoString)"
        case .chunkDelete(let chunk): return "delete \(chunk.lingoString)"
        }
    }
}

extension Expression {
    public var lingoString: String {
        switch self {
        case .void: return "VOID"
        case .integer(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .symbol(let v): return "#\(v)"
        case .boolean(let v): return v ? "TRUE" : "FALSE"
        case .identifier(let v): return v
        case .the(let v): return "the \(v)"
        case .theProp(let obj, let prop): return "the \(prop) of \(obj.lingoString)"
        case .objProp(let obj, let prop): return "\(obj.lingoString).\(prop)"
        case .propertyAccess(let target, let prop): return "\(target.lingoString).\(prop)"
        case .elementAccess(let target, let index): return "\(target.lingoString)[\(index.lingoString)]"
        case .objPropIndex(let obj, let prop, let idx, let idx2):
            let p2 = idx2 != nil ? ", \(idx2!.lingoString)" : ""
            return "\(obj.lingoString).\(prop)[\(idx.lingoString)\(p2)]"
        case .list(let items):
            return "[" + items.map { $0.lingoString }.joined(separator: ", ") + "]"
        case .propertyList(let entries):
            return "[" + entries.map { "\($0.key.lingoString): \($0.value.lingoString)" }.joined(separator: ", ") + "]"
        case .argList(let args):
            return "(" + args.map { $0.lingoString }.joined(separator: ", ") + ")"
        case .argListNoRet(let args):
            return args.map { $0.lingoString }.joined(separator: ", ")
        case .functionCall(let target, let name, let args):
            let argStr = args.map { $0.lingoString }.joined(separator: ", ")
            return target != nil ? "\(target!.lingoString).\(name)(\(argStr))" : "\(name)(\(argStr))"
        case .call(let name, let args): return "\(name) \(args.lingoString)"
        case .objCall(let name, let args): return ".\(name) \(args.lingoString)"
        case .objCallV4(let obj, let args): return "\(obj.lingoString)(\(args.lingoString))"
        case .binaryOperation(let left, let op, let right): return "\(left.lingoString) \(op.rawValue) \(right.lingoString)"
        case .unaryOperation(let op, let operand): return "\(op.rawValue)\(operand.lingoString)"
        case .chunkExpression(let type, let first, let last, let string):
            let lastStr = last != nil ? " to \(last!.lingoString)" : ""
            return "\(type) \(first.lingoString)\(lastStr) of \(string.lingoString)"
        case .elementRangeAccess(let target, let start, let end):
            return "\(target.lingoString)[\(start.lingoString)..\(end.lingoString)]"
        case .lastStringChunk(let type, let obj): return "the last \(type) of \(obj.lingoString)"
        case .stringChunkCount(let type, let obj): return "the number of \(type)s in \(obj.lingoString)"
        case .spriteIntersects(let first, let second): return "\(first.lingoString) intersects \(second.lingoString)"
        case .spriteWithin(let first, let second): return "\(first.lingoString) within \(second.lingoString)"
        case .member(let type, let id, let castId):
            let cId = castId != nil ? " of castLib \(castId!.lingoString)" : ""
            return "member \(id.lingoString)\(cId)" // Simplified
        case .menuProp(let menuId, let prop): return "the \(prop) of menu \(menuId.lingoString)"
        case .menuItemProp(let menuId, let itemId, let prop): return "the \(prop) of menuItem \(itemId.lingoString) of menu \(menuId.lingoString)"
        case .soundProp(let soundId, let prop): return "the \(prop) of sound \(soundId.lingoString)"
        case .spriteProp(let spriteId, let prop): return "the \(prop) of sprite \(spriteId.lingoString)"
        case .newObj(let type, let args): return "new(script \"\(type)\", \(args.lingoString))"
        }
    }
}
