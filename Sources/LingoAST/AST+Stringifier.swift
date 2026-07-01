import Foundation

extension Script {
    /// - Parameter syntax: `nil` reproduces each node's original dialect (as
    ///   parsed); `.verbose` or `.dot` forces every dialect-convertible node
    ///   in the tree to render in that dialect.
    public func toLingoSource(indent: Int = 0, syntax: LingoSyntax? = nil) -> String {
        var output = ""
        for stmt in statements {
            output += stmt.toLingoSource(indent: indent, syntax: syntax) + "\n"
        }
        return output
    }
}

extension Statement {
    public func toLingoSource(indent: Int = 0, syntax: LingoSyntax? = nil) -> String {
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
                result += stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end"
            return result
        case .assignment(let target, let value, let storedSyntax):
            let targetStr = target.toLingoSource(syntax: syntax)
            let valueStr = value.toLingoSource(syntax: syntax)
            switch syntax ?? storedSyntax {
            case .verbose: return pad + "set \(targetStr) to \(valueStr)"
            case .dot: return pad + "\(targetStr) = \(valueStr)"
            }
        case .put(let type, let value, let target):
            let targetStr = target != nil ? " \(type.rawValue) \(target!.toLingoSource(syntax: syntax))" : ""
            return pad + "put \(value.toLingoSource(syntax: syntax))\(targetStr)"
        case .ifStatement(let cond, let body, let elseBody):
            let header = pad + "if \(cond.toLingoSource(syntax: syntax)) then"
            if body.isEmpty && elseBody == nil {
                return header + "\n" + pad + "end if"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            // Emit `else` whenever the branch is present, even when empty,
            // so the AST (which distinguishes `nil` from `[]`) round-trips.
            if let elseBody = elseBody {
                result += pad + "else\n"
                for stmt in elseBody {
                    result += stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
                }
            }
            result += pad + "end if"
            return result
        case .repeatWithCounter(let variable, let start, let end, let body, let up):
            let dir = up ? "to" : "down to"
            let header = pad + "repeat with \(variable) = \(start.toLingoSource(syntax: syntax)) \(dir) \(end.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .repeatWhile(let cond, let body):
            let header = pad + "repeat while \(cond.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .repeatWithIn(let variable, let list, let body):
            let header = pad + "repeat with \(variable) in \(list.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .expressionStatement(let expr):
            return pad + expr.toLingoSource(syntax: syntax)
        case .returnStatement(let expr):
            guard let expr = expr else { return pad + "return" }
            return pad + "return \(expr.toLingoSource(syntax: syntax))"
        case .exit:
            return pad + "exit"
        case .exitRepeat:
            return pad + "exit repeat"
        case .nextRepeat:
            return pad + "next repeat"
        case .pass:
            return pad + "pass"
        case .caseStatement(let cond, let cases, let otherwise):
            let header = pad + "case \(cond.toLingoSource(syntax: syntax)) of"
            var result = header + "\n"
            for c in cases {
                let valuesStr = c.values.map { $0.toLingoSource(syntax: syntax) }.joined(separator: ", ")
                result += pad + "  " + valuesStr + ":\n"
                for stmt in c.body {
                    result += stmt.toLingoSource(indent: indent + 2, syntax: syntax) + "\n"
                }
            }
            if let otherwise = otherwise, !otherwise.isEmpty {
                result += pad + "  otherwise:\n"
                for stmt in otherwise {
                    result += stmt.toLingoSource(indent: indent + 2, syntax: syntax) + "\n"
                }
            }
            result += pad + "end case"
            return result
        case .tell(let window, let body):
            let header = pad + "tell \(window.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end tell"
            }
            var result = header + "\n"
            for stmt in body {
                result += stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end tell"
            return result
        case .when(let event, let script):
            return pad + "when \(event) then \(script)"
        case .soundCmd(let cmd, let args):
            guard let args = args else { return pad + "sound \(cmd)" }
            return pad + "sound \(cmd) \(args.toLingoSource(syntax: syntax))"
        case .playCmd(let args):
            guard let args = args else { return pad + "play" }
            return pad + "play \(args.toLingoSource(syntax: syntax))"
        case .chunkHilite(let chunk):
            return pad + "hilite \(chunk.toLingoSource(syntax: syntax))"
        case .chunkDelete(let chunk):
            return pad + "delete \(chunk.toLingoSource(syntax: syntax))"
        }
    }
}

extension Expression {
    public func toLingoSource(syntax: LingoSyntax? = nil) -> String {
        switch self {
        case .void: return "VOID"
        case .integer(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .symbol(let v): return "#\(v)"
        case .boolean(let v): return v ? "TRUE" : "FALSE"
        case .identifier(let v): return v
        case .the(let v): return "the \(v)"
        case .propertyAccess(let target, let prop, let storedSyntax):
            let targetStr = target.toLingoSource(syntax: syntax)
            switch syntax ?? storedSyntax {
            case .verbose: return "the \(prop) of \(targetStr)"
            case .dot: return "\(targetStr).\(prop)"
            }
        case .elementAccess(let target, let index): return "\(target.toLingoSource(syntax: syntax))[\(index.toLingoSource(syntax: syntax))]"
        case .objPropIndex(let obj, let prop, let idx, let idx2):
            let p2 = idx2 != nil ? ", \(idx2!.toLingoSource(syntax: syntax))" : ""
            return "\(obj.toLingoSource(syntax: syntax)).\(prop)[\(idx.toLingoSource(syntax: syntax))\(p2)]"
        case .list(let items):
            return "[" + items.map { $0.toLingoSource(syntax: syntax) }.joined(separator: ", ") + "]"
        case .propertyList(let entries):
            // An empty property list is `[:]`; `[]` would re-parse as a linear list.
            if entries.isEmpty { return "[:]" }
            return "[" + entries.map { "\($0.key.toLingoSource(syntax: syntax)): \($0.value.toLingoSource(syntax: syntax))" }.joined(separator: ", ") + "]"
        case .argList(let args):
            return "(" + args.map { $0.toLingoSource(syntax: syntax) }.joined(separator: ", ") + ")"
        case .argListNoRet(let args):
            return args.map { $0.toLingoSource(syntax: syntax) }.joined(separator: ", ")
        case .functionCall(let target, let name, let args):
            let argStr = args.map { $0.toLingoSource(syntax: syntax) }.joined(separator: ", ")
            return target != nil ? "\(target!.toLingoSource(syntax: syntax)).\(name)(\(argStr))" : "\(name)(\(argStr))"
        case .call(let name, let args): return "\(name) \(args.toLingoSource(syntax: syntax))"
        case .objCall(let name, let args): return ".\(name) \(args.toLingoSource(syntax: syntax))"
        case .objCallV4(let obj, let args): return "\(obj.toLingoSource(syntax: syntax))(\(args.toLingoSource(syntax: syntax)))"
        case .binaryOperation(let left, let op, let right):
            // Parenthesize so the original grouping survives a re-parse,
            // independent of operator-precedence rules.
            return "(\(left.toLingoSource(syntax: syntax)) \(op.rawValue) \(right.toLingoSource(syntax: syntax)))"
        case .unaryOperation(let op, let operand):
            // Parenthesize the operand so the operator binds to the whole
            // sub-expression on re-parse (e.g. `not (x.count())`, `-(a + b)`).
            if op == .not {
                return "not (\(operand.toLingoSource(syntax: syntax)))"
            }
            return "\(op.rawValue)(\(operand.toLingoSource(syntax: syntax)))"
        case .chunkExpression(let type, let first, let last, let string, let storedSyntax):
            switch syntax ?? storedSyntax {
            case .verbose:
                let lastStr = last != nil ? " to \(last!.toLingoSource(syntax: syntax))" : ""
                return "\(type) \(first.toLingoSource(syntax: syntax))\(lastStr) of \(string.toLingoSource(syntax: syntax))"
            case .dot:
                let lastStr = last != nil ? "..\(last!.toLingoSource(syntax: syntax))" : ""
                return "\(string.toLingoSource(syntax: syntax)).\(type)[\(first.toLingoSource(syntax: syntax))\(lastStr)]"
            }
        case .elementRangeAccess(let target, let start, let end):
            return "\(target.toLingoSource(syntax: syntax))[\(start.toLingoSource(syntax: syntax))..\(end.toLingoSource(syntax: syntax))]"
        case .lastStringChunk(let type, let obj):
            return "the last \(type) of \(obj.toLingoSource(syntax: syntax))"
        case .stringChunkCount(let type, let obj):
            return "the number of \(type)s in \(obj.toLingoSource(syntax: syntax))"
        case .spriteIntersects(let first, let second):
            return "\(first.toLingoSource(syntax: syntax)) intersects \(second.toLingoSource(syntax: syntax))"
        case .spriteWithin(let first, let second):
            return "\(first.toLingoSource(syntax: syntax)) within \(second.toLingoSource(syntax: syntax))"
        case .member(let type, let id, let castId):
            let cId = castId != nil ? " of castLib \(castId!.toLingoSource(syntax: syntax))" : ""
            return "\(type)(\(id.toLingoSource(syntax: syntax))\(cId))"
        case .menuProp(let menuId, let prop):
            return "the \(prop) of menu \(menuId.toLingoSource(syntax: syntax))"
        case .menuItemProp(let menuId, let itemId, let prop):
            return "the \(prop) of menuItem \(itemId.toLingoSource(syntax: syntax)) of menu \(menuId.toLingoSource(syntax: syntax))"
        case .soundProp(let soundId, let prop):
            return "the \(prop) of sound \(soundId.toLingoSource(syntax: syntax))"
        case .spriteProp(let spriteId, let prop):
            return "the \(prop) of sprite \(spriteId.toLingoSource(syntax: syntax))"
        case .newObj(let type, let args):
            return "new(script \"\(type)\", \(args.toLingoSource(syntax: syntax)))"
        case .range(let start, let end):
            return "\(start.toLingoSource(syntax: syntax)) to \(end.toLingoSource(syntax: syntax))"
        }
    }
}
