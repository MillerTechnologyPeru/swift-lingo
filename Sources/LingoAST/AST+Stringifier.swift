import Foundation

extension Script {
    /// - Parameter syntax: `nil` reproduces each node's original dialect (as
    ///   parsed); `.verbose` or `.dot` forces every dialect-convertible node
    ///   in the tree to render in that dialect.
    ///
    /// `async` so recursion (proportional to expression/statement nesting)
    /// runs on the task's heap-allocated frame allocator instead of the
    /// thread's fixed-size stack, which avoids overflow on deeply nested ASTs.
    public func toLingoSource(indent: Int = 0, syntax: LingoSyntax? = nil) async -> String {
        var output = ""
        for stmt in statements {
            output += await stmt.toLingoSource(indent: indent, syntax: syntax) + "\n"
        }
        return output
    }
}

extension Statement {
    public func toLingoSource(indent: Int = 0, syntax: LingoSyntax? = nil) async -> String {
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
                result += await stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end"
            return result
        case .assignment(let target, let value, let storedSyntax):
            let targetStr = await target.toLingoSource(syntax: syntax)
            let valueStr = await value.toLingoSource(syntax: syntax)
            switch syntax ?? storedSyntax {
            case .verbose: return pad + "set \(targetStr) to \(valueStr)"
            case .dot: return pad + "\(targetStr) = \(valueStr)"
            }
        case .put(let type, let value, let target):
            let targetStr: String
            if let target {
                targetStr = " \(type.rawValue) \(await target.toLingoSource(syntax: syntax))"
            } else {
                targetStr = ""
            }
            return pad + "put \(await value.toLingoSource(syntax: syntax))\(targetStr)"
        case .ifStatement(let cond, let body, let elseBody):
            let header = pad + "if \(await cond.toLingoSource(syntax: syntax)) then"
            if body.isEmpty && elseBody == nil {
                return header + "\n" + pad + "end if"
            }
            var result = header + "\n"
            for stmt in body {
                result += await stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            // Emit `else` whenever the branch is present, even when empty,
            // so the AST (which distinguishes `nil` from `[]`) round-trips.
            if let elseBody = elseBody {
                result += pad + "else\n"
                for stmt in elseBody {
                    result += await stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
                }
            }
            result += pad + "end if"
            return result
        case .repeatWithCounter(let variable, let start, let end, let body, let up):
            let dir = up ? "to" : "down to"
            let header = pad + "repeat with \(variable) = \(await start.toLingoSource(syntax: syntax)) \(dir) \(await end.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += await stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .repeatWhile(let cond, let body):
            let header = pad + "repeat while \(await cond.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += await stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .repeatWithIn(let variable, let list, let body):
            let header = pad + "repeat with \(variable) in \(await list.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end repeat"
            }
            var result = header + "\n"
            for stmt in body {
                result += await stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end repeat"
            return result
        case .expressionStatement(let expr):
            return pad + (await expr.toLingoSource(syntax: syntax))
        case .returnStatement(let expr):
            guard let expr = expr else { return pad + "return" }
            return pad + "return \(await expr.toLingoSource(syntax: syntax))"
        case .exit:
            return pad + "exit"
        case .exitRepeat:
            return pad + "exit repeat"
        case .nextRepeat:
            return pad + "next repeat"
        case .pass:
            return pad + "pass"
        case .caseStatement(let cond, let cases, let otherwise):
            let header = pad + "case \(await cond.toLingoSource(syntax: syntax)) of"
            var result = header + "\n"
            for c in cases {
                var valuesStr = ""
                for (i, value) in c.values.enumerated() {
                    if i > 0 { valuesStr += ", " }
                    valuesStr += await value.toLingoSource(syntax: syntax)
                }
                result += pad + "  " + valuesStr + ":\n"
                for stmt in c.body {
                    result += await stmt.toLingoSource(indent: indent + 2, syntax: syntax) + "\n"
                }
            }
            if let otherwise = otherwise, !otherwise.isEmpty {
                result += pad + "  otherwise:\n"
                for stmt in otherwise {
                    result += await stmt.toLingoSource(indent: indent + 2, syntax: syntax) + "\n"
                }
            }
            result += pad + "end case"
            return result
        case .tell(let window, let body):
            let header = pad + "tell \(await window.toLingoSource(syntax: syntax))"
            if body.isEmpty {
                return header + "\n" + pad + "end tell"
            }
            var result = header + "\n"
            for stmt in body {
                result += await stmt.toLingoSource(indent: indent + 1, syntax: syntax) + "\n"
            }
            result += pad + "end tell"
            return result
        case .when(let event, let script):
            return pad + "when \(event) then \(script)"
        case .soundCmd(let cmd, let args):
            guard let args = args else { return pad + "sound \(cmd)" }
            return pad + "sound \(cmd) \(await args.toLingoSource(syntax: syntax))"
        case .playCmd(let args):
            guard let args = args else { return pad + "play" }
            return pad + "play \(await args.toLingoSource(syntax: syntax))"
        case .chunkHilite(let chunk):
            return pad + "hilite \(await chunk.toLingoSource(syntax: syntax))"
        case .chunkDelete(let chunk):
            return pad + "delete \(await chunk.toLingoSource(syntax: syntax))"
        }
    }
}

extension Expression {
    public func toLingoSource(syntax: LingoSyntax? = nil) async -> String {
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
            let targetStr = await target.toLingoSource(syntax: syntax)
            switch syntax ?? storedSyntax {
            case .verbose: return "the \(prop) of \(targetStr)"
            case .dot: return "\(targetStr).\(prop)"
            }
        case .elementAccess(let target, let index):
            return "\(await target.toLingoSource(syntax: syntax))[\(await index.toLingoSource(syntax: syntax))]"
        case .objPropIndex(let obj, let prop, let idx, let idx2):
            let p2 = idx2 != nil ? ", \(await idx2!.toLingoSource(syntax: syntax))" : ""
            return "\(await obj.toLingoSource(syntax: syntax)).\(prop)[\(await idx.toLingoSource(syntax: syntax))\(p2)]"
        case .list(let items):
            var itemsStr = ""
            for (i, item) in items.enumerated() {
                if i > 0 { itemsStr += ", " }
                itemsStr += await item.toLingoSource(syntax: syntax)
            }
            return "[" + itemsStr + "]"
        case .propertyList(let entries):
            // An empty property list is `[:]`; `[]` would re-parse as a linear list.
            if entries.isEmpty { return "[:]" }
            var entriesStr = ""
            for (i, entry) in entries.enumerated() {
                if i > 0 { entriesStr += ", " }
                entriesStr += "\(await entry.key.toLingoSource(syntax: syntax)): \(await entry.value.toLingoSource(syntax: syntax))"
            }
            return "[" + entriesStr + "]"
        case .argList(let args):
            var argsStr = ""
            for (i, arg) in args.enumerated() {
                if i > 0 { argsStr += ", " }
                argsStr += await arg.toLingoSource(syntax: syntax)
            }
            return "(" + argsStr + ")"
        case .argListNoRet(let args):
            var argsStr = ""
            for (i, arg) in args.enumerated() {
                if i > 0 { argsStr += ", " }
                argsStr += await arg.toLingoSource(syntax: syntax)
            }
            return argsStr
        case .functionCall(let target, let name, let args):
            var argStr = ""
            for (i, arg) in args.enumerated() {
                if i > 0 { argStr += ", " }
                argStr += await arg.toLingoSource(syntax: syntax)
            }
            if let target {
                return "\(await target.toLingoSource(syntax: syntax)).\(name)(\(argStr))"
            }
            return "\(name)(\(argStr))"
        case .call(let name, let args): return "\(name) \(await args.toLingoSource(syntax: syntax))"
        case .objCall(let name, let args): return ".\(name) \(await args.toLingoSource(syntax: syntax))"
        case .objCallV4(let obj, let args): return "\(await obj.toLingoSource(syntax: syntax))(\(await args.toLingoSource(syntax: syntax)))"
        case .binaryOperation(let left, let op, let right):
            // Parenthesize so the original grouping survives a re-parse,
            // independent of operator-precedence rules.
            return "(\(await left.toLingoSource(syntax: syntax)) \(op.rawValue) \(await right.toLingoSource(syntax: syntax)))"
        case .unaryOperation(let op, let operand):
            // Parenthesize the operand so the operator binds to the whole
            // sub-expression on re-parse (e.g. `not (x.count())`, `-(a + b)`).
            if op == .not {
                return "not (\(await operand.toLingoSource(syntax: syntax)))"
            }
            return "\(op.rawValue)(\(await operand.toLingoSource(syntax: syntax)))"
        case .chunkExpression(let type, let first, let last, let string, let storedSyntax):
            switch syntax ?? storedSyntax {
            case .verbose:
                let lastStr = last != nil ? " to \(await last!.toLingoSource(syntax: syntax))" : ""
                return "\(type) \(await first.toLingoSource(syntax: syntax))\(lastStr) of \(await string.toLingoSource(syntax: syntax))"
            case .dot:
                let lastStr = last != nil ? "..\(await last!.toLingoSource(syntax: syntax))" : ""
                return "\(await string.toLingoSource(syntax: syntax)).\(type)[\(await first.toLingoSource(syntax: syntax))\(lastStr)]"
            }
        case .elementRangeAccess(let target, let start, let end):
            return "\(await target.toLingoSource(syntax: syntax))[\(await start.toLingoSource(syntax: syntax))..\(await end.toLingoSource(syntax: syntax))]"
        case .lastStringChunk(let type, let obj):
            return "the last \(type) of \(await obj.toLingoSource(syntax: syntax))"
        case .stringChunkCount(let type, let obj):
            return "the number of \(type)s in \(await obj.toLingoSource(syntax: syntax))"
        case .spriteIntersects(let first, let second):
            return "\(await first.toLingoSource(syntax: syntax)) intersects \(await second.toLingoSource(syntax: syntax))"
        case .spriteWithin(let first, let second):
            return "\(await first.toLingoSource(syntax: syntax)) within \(await second.toLingoSource(syntax: syntax))"
        case .member(let type, let id, let castId):
            let cId = castId != nil ? " of castLib \(await castId!.toLingoSource(syntax: syntax))" : ""
            return "\(type)(\(await id.toLingoSource(syntax: syntax))\(cId))"
        case .menuProp(let menuId, let prop):
            return "the \(prop) of menu \(await menuId.toLingoSource(syntax: syntax))"
        case .menuItemProp(let menuId, let itemId, let prop):
            return "the \(prop) of menuItem \(await itemId.toLingoSource(syntax: syntax)) of menu \(await menuId.toLingoSource(syntax: syntax))"
        case .soundProp(let soundId, let prop):
            return "the \(prop) of sound \(await soundId.toLingoSource(syntax: syntax))"
        case .spriteProp(let spriteId, let prop):
            return "the \(prop) of sprite \(await spriteId.toLingoSource(syntax: syntax))"
        case .newObj(let type, let args):
            return "new(script \"\(type)\", \(await args.toLingoSource(syntax: syntax)))"
        case .range(let start, let end):
            return "\(await start.toLingoSource(syntax: syntax)) to \(await end.toLingoSource(syntax: syntax))"
        }
    }
}
