import Foundation

extension Script {
    public func toLingoSource() -> String {
        var output = ""
        for stmt in statements {
            output += stmt.toLingoSource(indent: 0) + "\n"
        }
        return output
    }
}

extension Statement {
    public func toLingoSource(indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .global(let names):
            return pad + "global " + names.joined(separator: ", ")
        case .property(let names):
            return pad + "property " + names.joined(separator: ", ")
        case .handler(let name, let args, let body):
            let header = pad + "on \(name) " + args.joined(separator: ", ")
            if body.isEmpty {
                return header + "\n" + pad + "end"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1) + "\n"
            }
            result += pad + "end"
            return result
        case .assignment(let target, let value):
            return pad + "\(target.toLingoSource()) = \(value.toLingoSource())"
        case .put(let type, let value, let target):
            let targetStr = target != nil ? " \(type.rawValue) \(target!.toLingoSource())" : ""
            return pad + "put \(value.toLingoSource())\(targetStr)"
        case .ifStatement(let cond, let body, let elseBody):
            let header = pad + "if \(cond.toLingoSource()) then"
            if body.isEmpty && (elseBody == nil || elseBody!.isEmpty) {
                return header + "\n" + pad + "end if"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1) + "\n"
            }
            if let elseBody = elseBody, !elseBody.isEmpty {
                result += pad + "else\n"
                for stmt in elseBody {
                    result += stmt.toLingoSource(indent: indent + 1) + "\n"
                }
            }
            result += pad + "end if"
            return result
        case .repeatWithCounter(let variable, let start, let end, let body, let up):
            let dir = up ? "to" : "down to"
            let header = pad + "repeat with \(variable) = \(start.toLingoSource()) \(dir) \(end.toLingoSource())"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .repeatWhile(let cond, let body):
            let header = pad + "repeat while \(cond.toLingoSource())"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .repeatWithIn(let variable, let list, let body):
            let header = pad + "repeat with \(variable) in \(list.toLingoSource())"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .expressionStatement(let expr):
            return pad + expr.toLingoSource()
        case .returnStatement(let expr):
            guard let expr = expr else { return pad + "return" }
            return pad + "return \(expr.toLingoSource())"
        case .exit:
            return pad + "exit"
        case .exitRepeat:
            return pad + "exit repeat"
        case .nextRepeat:
            return pad + "next repeat"
        case .caseStatement(let cond, let cases, let otherwise):
            let header = pad + "case \(cond.toLingoSource()) of"
            var result = header + "\n"
            for c in cases {
                let valuesStr = c.values.map { $0.toLingoSource() }.joined(separator: ", ")
                result += pad + "  " + valuesStr + ":\n"
                for stmt in c.body {
                    result += stmt.toLingoSource(indent: indent + 2) + "\n"
                }
            }
            if let otherwise = otherwise, !otherwise.isEmpty {
                result += pad + "  otherwise:\n"
                for stmt in otherwise {
                    result += stmt.toLingoSource(indent: indent + 2) + "\n"
                }
            }
            result += pad + "end case"
            return result
        case .tell(let window, let body):
            let header = pad + "tell \(window.toLingoSource())"
            if body.isEmpty {
                return header + "\n" + pad + "end tell"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1) + "\n"
            }
            result += pad + "end tell"
            return result
        case .when(let event, let script):
            return pad + "when \(event) then \(script)"
        case .soundCmd(let cmd, let args):
            guard let args = args else { return pad + "sound \(cmd)" }
            return pad + "sound \(cmd) \(args.toLingoSource())"
        case .playCmd(let args):
            guard let args = args else { return pad + "play" }
            return pad + "play \(args.toLingoSource())"
        case .chunkHilite(let chunk):
            return pad + "hilite \(chunk.toLingoSource())"
        case .chunkDelete(let chunk):
            return pad + "delete \(chunk.toLingoSource())"
        }
    }
}

extension Expression {
    public func toLingoSource() -> String {
        switch self {
        case .void: return "VOID"
        case .integer(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .symbol(let v): return "#\(v)"
        case .boolean(let v): return v ? "TRUE" : "FALSE"
        case .identifier(let v): return v
        case .the(let v): return "the \(v)"
        case .theProp(let obj, let prop): return "the \(prop) of \(obj.toLingoSource())"
        case .objProp(let obj, let prop): return "\(obj.toLingoSource()).\(prop)"
        case .propertyAccess(let target, let prop): return "\(target.toLingoSource()).\(prop)"
        case .elementAccess(let target, let index): return "\(target.toLingoSource())[\(index.toLingoSource())]"
        case .objPropIndex(let obj, let prop, let idx, let idx2):
            let p2 = idx2 != nil ? ", \(idx2!.toLingoSource())" : ""
            return "\(obj.toLingoSource()).\(prop)[\(idx.toLingoSource())\(p2)]"
        case .list(let items):
            return "[" + items.map { $0.toLingoSource() }.joined(separator: ", ") + "]"
        case .propertyList(let entries):
            return "[" + entries.map { "\($0.key.toLingoSource()): \($0.value.toLingoSource())" }.joined(separator: ", ") + "]"
        case .argList(let args):
            return "(" + args.map { $0.toLingoSource() }.joined(separator: ", ") + ")"
        case .argListNoRet(let args):
            return args.map { $0.toLingoSource() }.joined(separator: ", ")
        case .functionCall(let target, let name, let args):
            let argStr = args.map { $0.toLingoSource() }.joined(separator: ", ")
            return target != nil ? "\(target!.toLingoSource()).\(name)(\(argStr))" : "\(name)(\(argStr))"
        case .call(let name, let args): return "\(name) \(args.toLingoSource())"
        case .objCall(let name, let args): return ".\(name) \(args.toLingoSource())"
        case .objCallV4(let obj, let args): return "\(obj.toLingoSource())(\(args.toLingoSource()))"
        case .binaryOperation(let left, let op, let right):
            return "\(left.toLingoSource()) \(op.rawValue) \(right.toLingoSource())"
        case .unaryOperation(let op, let operand):
            return "\(op.rawValue)\(operand.toLingoSource())"
        case .chunkExpression(let type, let first, let last, let string):
            let lastStr = last != nil ? " to \(last!.toLingoSource())" : ""
            return "\(type) \(first.toLingoSource())\(lastStr) of \(string.toLingoSource())"
        case .elementRangeAccess(let target, let start, let end):
            return "\(target.toLingoSource())[\(start.toLingoSource())..\(end.toLingoSource())]"
        case .lastStringChunk(let type, let obj):
            return "the last \(type) of \(obj.toLingoSource())"
        case .stringChunkCount(let type, let obj):
            return "the number of \(type)s in \(obj.toLingoSource())"
        case .spriteIntersects(let first, let second):
            return "\(first.toLingoSource()) intersects \(second.toLingoSource())"
        case .spriteWithin(let first, let second):
            return "\(first.toLingoSource()) within \(second.toLingoSource())"
        case .member(let type, let id, let castId):
            let cId = castId != nil ? " of castLib \(castId!.toLingoSource())" : ""
            return "\(type)(\(id.toLingoSource())\(cId))"
        case .menuProp(let menuId, let prop):
            return "the \(prop) of menu \(menuId.toLingoSource())"
        case .menuItemProp(let menuId, let itemId, let prop):
            return "the \(prop) of menuItem \(itemId.toLingoSource()) of menu \(menuId.toLingoSource())"
        case .soundProp(let soundId, let prop):
            return "the \(prop) of sound \(soundId.toLingoSource())"
        case .spriteProp(let spriteId, let prop):
            return "the \(prop) of sprite \(spriteId.toLingoSource())"
        case .newObj(let type, let args):
            return "new(script \"\(type)\", \(args.toLingoSource()))"
        }
    }
}
