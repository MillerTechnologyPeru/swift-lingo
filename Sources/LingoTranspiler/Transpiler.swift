import Foundation
import LingoAST
import LingoParser

public final class LingoTranspiler {

    private var activeProperties: Set<String> = []
    private var activeHandlerIsInitializer = false
    private var script: Script
    private var relativePath: String
    private var originalPath: String

    public init(script: Script, relativePath: String, originalPath: String) {
        self.script = script
        self.relativePath = relativePath
        self.originalPath = originalPath
    }

    public func transpile() -> String {
        let pathComponents = originalPath.split(separator: "/")
        let shortPath = pathComponents.count >= 2 ? pathComponents.suffix(2).joined(separator: "/") : originalPath
        var output = "// Transpiled from \(shortPath)\n"
        output += "import LingoRuntime\n\n"

        let isMovie = relativePath.lowercased().contains("movie_")

        if !isMovie {
            let className = formatClassName(relativePath)
            output += "public class \(className): LingoObject {\n"

            var properties: [String] = []
            for stmt in script.statements {
                if case .property(let names) = stmt {
                    properties.append(contentsOf: names)
                }
            }

            // Emit CodingKeys enum if there are properties
            if !properties.isEmpty {
                output += "    /// Property keys for type-safe property access.\n"
                output += "    public enum CodingKeys: String, Sendable, CaseIterable {\n"
                for prop in properties {
                    output += "        case `\(prop)` = \"\(prop.lowercased())\"\n"
                }
                output += "\n"
                output += "        /// Case-insensitive lookup without Unicode data tables.\n"
                output += "        public static func find(_ name: String) -> CodingKeys? {\n"
                output += "            for key in allCases {\n"
                output += "                if name.caseInsensitiveEquals(key.rawValue) {\n"
                output += "                    return key\n"
                output += "                }\n"
                output += "            }\n"
                output += "            return nil\n"
                output += "        }\n"
                output += "    }\n\n"
            }

            for prop in properties {
                output += "    public var `\(prop)`: LingoValue = .void\n"
            }
            if !properties.isEmpty { output += "\n" }

            output += "    public override func getProperty(_ name: String) -> LingoValue {\n"
            if !properties.isEmpty {
                output += "        guard let key = CodingKeys.find(name) else {\n"
                output += "            return super.getProperty(name)\n"
                output += "        }\n"
                output += "        switch key {\n"
                for prop in properties {
                    output += "        case .`\(prop)`: return self.`\(prop)`\n"
                }
                output += "        }\n"
            } else {
                output += "        return super.getProperty(name)\n"
            }
            output += "    }\n\n"

            output += "    public override func setProperty(_ name: String, value: LingoValue) {\n"
            if !properties.isEmpty {
                output += "        guard let key = CodingKeys.find(name) else {\n"
                output += "            super.setProperty(name, value: value)\n"
                output += "            return\n"
                output += "        }\n"
                output += "        switch key {\n"
                for prop in properties {
                    output += "        case .`\(prop)`: self.`\(prop)` = value\n"
                }
                output += "        }\n"
            } else {
                output += "        super.setProperty(name, value: value)\n"
            }
            output += "    }\n\n"

            let handlers = script.statements.compactMap { stmt -> (name: String, arguments: [String], body: [Statement])? in
                if case .handler(let name, let arguments, let body) = stmt {
                    return (name, arguments, body)
                }
                return nil
            }
            output += transpileCallMethod(handlers: handlers)

            let propertyNames = Set(properties.map { $0.lowercased() })
            for stmt in script.statements {
                if case .handler(let name, let arguments, let body) = stmt {
                    output += transpileHandler(name: name, args: arguments, body: body, isMethod: true, properties: propertyNames)
                }
            }

            output += "}\n"
        } else {
            for stmt in script.statements {
                if case .handler(let name, let arguments, let body) = stmt {
                    output += transpileHandler(name: name, args: arguments, body: body, isMethod: false, properties: [])
                }
            }
        }

        return output
    }

    private func transpileCallMethod(handlers: [(name: String, arguments: [String], body: [Statement])]) -> String {
        let validHandlers = handlers.filter { $0.name.lowercased() != "new" }
        guard !validHandlers.isEmpty else {
            var output = "    public override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {\n"
            output += "        return super.callMethod(name, args: args)\n"
            output += "    }\n\n"
            return output
        }

        var output = "    private enum MethodName: String {\n"
        for handler in validHandlers {
            output += "        case `\(handler.name.lowercased())` = \"\(handler.name.lowercased())\"\n"
        }
        output += "    }\n\n"

        output += "    public override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {\n"
        output += "        guard let methodName = MethodName(rawValue: name.asciiLowercased()) else {\n"
        output += "            return super.callMethod(name, args: args)\n"
        output += "        }\n"
        output += "        switch methodName {\n"

        for handler in validHandlers {
            let lingoArgs = handler.arguments.filter { $0.lowercased() != "me" }
            let callArgs = lingoArgs.indices.map { "args.count > \($0) ? args[\($0)] : .void" }.joined(separator: ", ")
            output += "        case .`\(handler.name.lowercased())`:\n"
            output += "            return self.`\(handler.name)`(\(callArgs))\n"
        }
        output += "        }\n"
        output += "    }\n\n"
        return output
    }

    private func transpileHandler(name: String, args: [String], body: [Statement], isMethod: Bool, properties: Set<String>) -> String {
        let previousProperties = activeProperties
        let previousHandlerIsInitializer = activeHandlerIsInitializer
        let isInitializer = isMethod && name.lowercased() == "new"
        activeProperties = properties
        activeHandlerIsInitializer = isInitializer
        var output = ""
        let functionIndent = isMethod ? "    " : ""
        let swiftArgs = args.filter { $0.lowercased() != "me" }.map { "_ `\($0.lowercased())`: LingoValue = LingoValue.void" }.joined(separator: ", ")
        if isInitializer {
            let overrideKeyword = swiftArgs.isEmpty ? "override " : ""
            output += "\(functionIndent)public \(overrideKeyword)init(\(swiftArgs)) {\n"
            output += "\(functionIndent)    super.init()\n"
        } else {
            let funcName = isMethod ? "`\(name)`" : "lingo_\(name)"
            output += "\(functionIndent)public func \(funcName)(\(swiftArgs)) -> LingoValue {\n"
        }

        let indent = isMethod ? "        " : "    "

        var mutatedVars = Set<String>()
        var globals = Set<String>()
        collectVariables(in: body, locals: &mutatedVars, globals: &globals)

        var locals = mutatedVars
        locals.subtract(globals)
        locals.subtract(properties)
        for arg in args { locals.insert(arg.lowercased()) }

        let argumentNames = Set(args.map { $0.lowercased() })
        let hoisted = locals.filter { !argumentNames.contains($0) }.sorted()
        for variable in hoisted {
            output += "\(indent)var `\(variable)`: LingoValue = .void\n"
            output += "\(indent)_ = `\(variable)`\n"
        }

        for arg in args where arg.lowercased() != "me" {
            let isMutated = mutatedVars.contains(arg.lowercased())
            let keyword = isMutated ? "var" : "let"
            output += "\(indent)\(keyword) `\(arg.lowercased())`: LingoValue = `\(arg.lowercased())`\n"
            output += "\(indent)_ = `\(arg.lowercased())`\n"
        }

        if !hoisted.isEmpty || args.count > (args.contains { $0.lowercased() == "me" } ? 1 : 0) { output += "\n" }

        for stmt in body {
            output += transpile(statement: stmt, indent: indent, locals: locals, isMethod: isMethod)
        }

        if !isInitializer {
            if !alwaysReturns(body) {
                output += "\(indent)return .void\n"
            }
        }
        let endIndent = isMethod ? "    " : ""
        output += "\(endIndent)}\n\n"
        activeProperties = previousProperties
        activeHandlerIsInitializer = previousHandlerIsInitializer
        return output
    }

    private func collectVariables(in statements: [Statement], locals: inout Set<String>, globals: inout Set<String>) {
        for stmt in statements {
            switch stmt {
            case .global(let names):
                for name in names { globals.insert(name.lowercased()) }
            case .assignment(let target, _, _):
                if case .identifier(let name) = target {
                    locals.insert(name.lowercased())
                }
            case .put(_, _, let target):
                if let target = target, case .identifier(let name) = target {
                    locals.insert(name.lowercased())
                }
            case .repeatWithCounter(let variable, _, _, let body, _):
                locals.insert(variable.lowercased())
                collectVariables(in: body, locals: &locals, globals: &globals)
            case .repeatWithIn(let variable, _, let body):
                locals.insert(variable.lowercased())
                collectVariables(in: body, locals: &locals, globals: &globals)
            case .ifStatement(_, let body, let elseBody):
                collectVariables(in: body, locals: &locals, globals: &globals)
                if let elseBody = elseBody { collectVariables(in: elseBody, locals: &locals, globals: &globals) }
            case .repeatWhile(_, let body):
                collectVariables(in: body, locals: &locals, globals: &globals)
            case .caseStatement(_, let cases, let otherwise):
                for c in cases { collectVariables(in: c.body, locals: &locals, globals: &globals) }
                if let otherwise = otherwise { collectVariables(in: otherwise, locals: &locals, globals: &globals) }
            default:
                break
            }
        }
    }

    private func alwaysReturns(_ statements: [Statement]) -> Bool {
        guard let last = statements.last else { return false }
        switch last {
        case .returnStatement, .exit, .pass:
            return true
        case .ifStatement(_, let body, let elseBody):
            if let elseBody = elseBody {
                return alwaysReturns(body) && alwaysReturns(elseBody)
            }
            return false
        case .caseStatement(_, let cases, let otherwise):
            for c in cases {
                if !alwaysReturns(c.body) { return false }
            }
            if let otherwise = otherwise {
                return alwaysReturns(otherwise)
            }
            return false
        default:
            return false
        }
    }

    private func transpile(statement: Statement, indent: String, locals: Set<String>, isMethod: Bool) -> String {
        let maxCommentDepth = 8
        let commentedSource: String
        if expressionDepth(of: statement) <= maxCommentDepth {
            commentedSource = statement.toLingoSource().split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(indent)// \($0)" }.joined(separator: "\n")
        } else {
            commentedSource = "\(indent)// (complex expression omitted)"
        }
        var output = "\(commentedSource)\n"
        switch statement {
        case .global, .property:
            break
        case .handler:
            break
        case .assignment(let target, let value, _):
            let valStr = transpile(expression: value, locals: locals, isMethod: isMethod)
            output += transpileAssignment(target: target, valStr: valStr, indent: indent, locals: locals, isMethod: isMethod)
        case .put(_, let value, let target):
            let valStr = transpile(expression: value, locals: locals, isMethod: isMethod)
            if let t = target {
                output += transpileAssignment(target: t, valStr: valStr, indent: indent, locals: locals, isMethod: isMethod)
            }
        case .ifStatement(let cond, let body, let elseBody):
            let condStr = transpile(expression: cond, locals: locals, isMethod: isMethod)
            output += "\(indent)if (\(condStr) as LingoValue).asBool() {\n"
            for stmt in body {
                output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
            }
            if let elseBody = elseBody, !elseBody.isEmpty {
                output += "\(indent)} else {\n"
                for stmt in elseBody {
                    output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
                }
            }
            output += "\(indent)}\n"
        case .repeatWithCounter(let variable, let start, let end, let body, let up):
            let startStr = transpile(expression: start, locals: locals, isMethod: isMethod)
            let endStr = transpile(expression: end, locals: locals, isMethod: isMethod)
            output += "\(indent)`\(variable.lowercased())` = \(startStr)\n"
            let op = up ? "<=" : ">="
            let inc = up ? "+" : "-"
            output += "\(indent)while ((`\(variable.lowercased())` \(op) \(endStr)) as LingoValue).asBool() {\n"
            for stmt in body {
                output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
            }
            output += "\(indent)    `\(variable.lowercased())` = `\(variable.lowercased())` \(inc) .integer(1)\n"
            output += "\(indent)}\n"
        case .repeatWhile(let cond, let body):
            let condStr = transpile(expression: cond, locals: locals, isMethod: isMethod)
            output += "\(indent)while (\(condStr) as LingoValue).asBool() {\n"
            for stmt in body {
                output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
            }
            output += "\(indent)}\n"
        case .repeatWithIn(let variable, let list, let body):
            let listStr = transpile(expression: list, locals: locals, isMethod: isMethod)
            output += "\(indent)for lingoItem in \(listStr).asSequence() {\n"
            output += "\(indent)    `\(variable.lowercased())` = lingoItem\n"
            for stmt in body {
                output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
            }
            output += "\(indent)}\n"
        case .expressionStatement(let expr):
            let exprStr = transpile(expression: expr, locals: locals, isMethod: isMethod)
            output += "\(indent)let _: LingoValue = \(exprStr)\n"
        case .returnStatement(let expr):
            if activeHandlerIsInitializer {
                if let expr, !expr.isMeReference {
                    let exprStr = transpile(expression: expr, locals: locals, isMethod: isMethod)
                    output += "\(indent)_ = \(exprStr)\n"
                }
            } else if let expr = expr {
                let exprStr = transpile(expression: expr, locals: locals, isMethod: isMethod)
                output += "\(indent)return \(exprStr)\n"
            } else {
                output += "\(indent)return .void\n"
            }
        case .exit:
            output += activeHandlerIsInitializer ? "\(indent)return\n" : "\(indent)return .void\n"
        case .exitRepeat:
            output += "\(indent)break\n"
        case .nextRepeat:
            output += "\(indent)continue\n"
        case .pass:
            // Notify the runtime, then halt the current handler: per Lingo
            // semantics, no statements following `pass` execute.
            output += "\(indent)_ = LingoEnvironment.shared.callGlobal(\"pass\", args: [])\n"
            output += activeHandlerIsInitializer ? "\(indent)return\n" : "\(indent)return .void\n"
        case .caseStatement(let cond, let cases, let otherwise):
            let condStr = transpile(expression: cond, locals: locals, isMethod: isMethod)
            output += "\(indent)switch \(condStr) {\n"
            for c in cases {
                let caseVals = c.values.map { transpile(expression: $0, locals: locals, isMethod: isMethod) }.joined(separator: ", ")
                output += "\(indent)case \(caseVals):\n"
                if c.body.isEmpty {
                    output += "\(indent)    break\n"
                } else {
                    for stmt in c.body {
                        output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
                    }
                }
            }
            output += "\(indent)default:\n"
            if let otherwise = otherwise {
                for stmt in otherwise {
                    output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
                }
            } else {
                output += "\(indent)    break\n"
            }
            output += "\(indent)}\n"
        case .tell(let window, let body):
            let windowStr = transpile(expression: window, locals: locals, isMethod: isMethod)
            output += "\(indent)_ = \(windowStr)\n"
            output += "\(indent)do {\n"
            for stmt in body {
                output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
            }
            output += "\(indent)}\n"
        case .when(let event, let script):
            output += "\(indent)_ = LingoEnvironment.shared.callGlobal(\"when\", args: [.string(\"\(escapeSwiftString(event))\"), .string(\"\(escapeSwiftString(script))\")])\n"
        case .soundCmd(let cmd, let args):
            let argsStr = args.map { transpile(expression: $0, locals: locals, isMethod: isMethod) } ?? ".void"
            output += "\(indent)_ = LingoEnvironment.shared.callGlobal(\"\(escapeSwiftString(cmd))\", args: [\(argsStr)])\n"
        case .playCmd(let args):
            let argsStr = args.map { transpile(expression: $0, locals: locals, isMethod: isMethod) } ?? ".void"
            output += "\(indent)_ = LingoEnvironment.shared.callGlobal(\"play\", args: [\(argsStr)])\n"
        case .chunkHilite(let chunk):
            let chunkStr = transpile(expression: chunk, locals: locals, isMethod: isMethod)
            output += "\(indent)_ = LingoEnvironment.shared.callGlobal(\"hilite\", args: [\(chunkStr)])\n"
        case .chunkDelete(let chunk):
            let chunkStr = transpile(expression: chunk, locals: locals, isMethod: isMethod)
            output += "\(indent)_ = LingoEnvironment.shared.callGlobal(\"delete\", args: [\(chunkStr)])\n"
        }
        return output
    }

    private func transpileAssignment(target: LingoAST.Expression, valStr: String, indent: String, locals: Set<String>, isMethod: Bool) -> String {
        var output = ""
        if case .identifier(let name) = target {
            let lower = name.lowercased()
            if locals.contains(lower) {
                output += "\(indent)`\(lower)` = \(valStr)\n"
            } else if isMethod && activeProperties.contains(lower) {
                output += "\(indent)self.`\(name)` = \(valStr)\n"
            } else {
                output += "\(indent)LingoEnvironment.shared.setGlobal(\"\(name)\", \(valStr))\n"
            }
        } else if let memberProperty = transpileMemberSpritePropertyAssignment(target: target, value: valStr, locals: locals, isMethod: isMethod) {
            output += "\(indent)\(memberProperty)\n"
        } else if case .propertyAccess(let obj, let prop, _) = target {
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            output += "\(indent)\(objStr).setProperty(\"\(prop)\", value: \(valStr))\n"
        } else if case .elementAccess(let obj, let indexExpr) = target {
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            let idxStr = transpile(expression: indexExpr, locals: locals, isMethod: isMethod)
            output += "\(indent)\(objStr).setElement(index: \(idxStr), value: \(valStr))\n"
        } else if case .the(let name) = target {
            output += "\(indent)LingoEnvironment.shared.setGlobal(\"\(name)\", \(valStr))\n"
        } else if case .chunkExpression(let type, let first, let last, let string, _) = target {
            let firstStr = transpile(expression: first, locals: locals, isMethod: isMethod)
            let lastStr = last.map { transpile(expression: $0, locals: locals, isMethod: isMethod) } ?? "nil"
            let newStringValue = "(\(transpile(expression: string, locals: locals, isMethod: isMethod))).settingChunk(\"\(type.lingoName)\", start: \(firstStr), end: \(lastStr), value: \(valStr))"
            output += transpileAssignment(target: string, valStr: newStringValue, indent: indent, locals: locals, isMethod: isMethod)
        } else {
            let targetStr = transpile(expression: target, locals: locals, isMethod: isMethod)
            output += "\(indent)\(targetStr) = \(valStr)\n"
        }
        return output
    }

    private func transpileMemberSpritePropertyAssignment(target: LingoAST.Expression, value: String, locals: Set<String>, isMethod: Bool) -> String? {
        guard case .member(let type, let id, nil) = target,
            type.lowercased() == "member" || type.lowercased() == "sprite"
        else { return nil }

        let chain = propertyChain(from: id)
        guard case .identifier(let baseName) = chain.base,
            baseName.lowercased() == "me",
            chain.properties.count >= 3,
            chain.properties[0].lowercased() == "spritenum",
            chain.properties[1].lowercased() == "member"
        else { return nil }

        let propertyName = chain.properties[chain.properties.count - 1]
        var receiver =
            isMethod
            ? "self.`sprite`(LingoValue.object(self).`spriteNum`).`member`" : "LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoEnvironment.shared.getGlobal(\"spriteNum\")]).`member`"
        if chain.properties.count > 3 {
            for property in chain.properties.dropFirst(2).dropLast() {
                receiver += ".`\(property)`"
            }
        }
        return "\(receiver).setProperty(\"\(escapeSwiftString(propertyName))\", value: \(value))"
    }

    private func propertyChain(from expression: LingoAST.Expression) -> (base: LingoAST.Expression, properties: [String]) {
        switch expression {
        case .propertyAccess(let target, let property, _):
            let chain = propertyChain(from: target)
            return (chain.base, chain.properties + [property])
        default:
            return (expression, [])
        }
    }

    func transpile(expression: LingoAST.Expression, locals: Set<String>, isMethod: Bool) -> String {
        switch expression {
        case .void: return "LingoValue.void"
        case .integer(let v): return "LingoValue.integer(\(v))"
        case .float(let v): return "LingoValue.float(\(v))"
        case .string(let v): return "LingoValue.string(\"\(escapeSwiftString(v))\")"
        case .symbol(let v): return "LingoValue.symbol(\"\(escapeSwiftString(v))\")"
        case .boolean(let v): return "LingoValue.integer(\(v ? 1 : 0))"
        case .identifier(let name):
            let lower = name.lowercased()
            if lower == "me" { return "LingoValue.object(self)" }
            if lower == "void" { return "LingoValue.void" }
            if locals.contains(lower) {
                return "`\(lower)`"
            }
            if isMethod && activeProperties.contains(lower) {
                return "self.`\(name)`"
            }
            return "LingoEnvironment.shared.getGlobal(\"\(name)\")"
        case .the(let prop):
            return isMethod ? "self.`\(prop)`" : "LingoEnvironment.shared.getGlobal(\"\(prop)\")"
        case .propertyAccess(let target, let prop, _):
            let tStr = transpile(expression: target, locals: locals, isMethod: isMethod)
            return "\(tStr).`\(prop)`"
        case .functionCall(let target, let name, let args):
            let lingoArgs = args.filter { !$0.isMeReference }
            let argStr = lingoArgs.map { transpile(expression: $0, locals: locals, isMethod: isMethod) }.joined(separator: ", ")
            if let t = target {
                let tStr = t.isMeReference ? "self" : transpile(expression: t, locals: locals, isMethod: isMethod)
                return "\(tStr).`\(name)`(\(argStr))"
            } else {
                if locals.contains(name.lowercased()) {
                    return "`\(name.lowercased())`(\(argStr))"  // LingoValue being called
                } else {
                    return isMethod ? "self.`\(name)`(\(argStr))" : "LingoEnvironment.shared.callGlobal(\"\(name)\", args: [\(argStr)])"
                }
            }
        case .call(let name, let argExpr), .objCall(let name, let argExpr):
            let argStr = transpile(expression: argExpr, locals: locals, isMethod: isMethod)
            return isMethod ? "self.`\(name)`(\(argStr))" : "LingoEnvironment.shared.callGlobal(\"\(name)\", args: [\(argStr)])"
        case .objCallV4(let obj, let argExpr):
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            let argStr = transpile(expression: argExpr, locals: locals, isMethod: isMethod)
            return "\(objStr)(\(argStr))"
        case .binaryOperation:
            // Unroll the left-leaning chain iteratively to avoid stack overflow
            // on deeply nested expressions (e.g. 60+ chained & concatenations).
            typealias Rhs = (op: LingoAST.BinaryOperator, expr: LingoAST.Expression)
            var rhsTerms: [Rhs] = []
            var current = expression
            while case .binaryOperation(let left, let op, let right) = current {
                rhsTerms.append((op: op, expr: right))
                current = left
            }
            rhsTerms.reverse()
            var result = transpile(expression: current, locals: locals, isMethod: isMethod)
            for (op, rExpr) in rhsTerms {
                let r = transpile(expression: rExpr, locals: locals, isMethod: isMethod)
                switch op {
                case .equals: result = "(\(result) == \(r))"
                case .notEquals: result = "(\(result) != \(r))"
                case .logicalAnd:
                    result = "((\(result)).asBool() && (\(r)).asBool() ? LingoValue.integer(1) : LingoValue.integer(0))"
                case .logicalOr:
                    result = "((\(result)).asBool() || (\(r)).asBool() ? LingoValue.integer(1) : LingoValue.integer(0))"
                case .stringConcat: result = "\(result).concat(\(r))"
                case .stringConcatSpace: result = "\(result).concatSpace(\(r))"
                case .modulo: result = "(\(result) % \(r))"
                case .contains: result = "\(result).contains(\(r))"
                case .starts: result = "\(result).starts(with: \(r))"
                default: result = "(\(result) \(op.rawValue) \(r))"
                }
            }
            return result
        case .unaryOperation(let op, let operand):
            let opr = transpile(expression: operand, locals: locals, isMethod: isMethod)
            if op == .not {
                return "((\(opr)).asBool() ? LingoValue.integer(0) : LingoValue.integer(1))"
            }
            return "(\(op.rawValue)\(opr))"
        case .list(let items):
            let itemsStr = items.map { transpile(expression: $0, locals: locals, isMethod: isMethod) }.joined(separator: ", ")
            return "LingoValue.list([\(itemsStr)])"
        case .propertyList(let entries):
            let entriesStr = entries.map {
                "(key: \(transpile(expression: $0.key, locals: locals, isMethod: isMethod)), value: \(transpile(expression: $0.value, locals: locals, isMethod: isMethod)))"
            }.joined(separator: ", ")
            return "LingoValue.propertyList([\(entriesStr)])"
        case .elementAccess(let target, let index):
            let tStr = transpile(expression: target, locals: locals, isMethod: isMethod)
            let iStr = transpile(expression: index, locals: locals, isMethod: isMethod)
            return "\(tStr)[\(iStr)]"
        case .elementRangeAccess(let target, let start, let end):
            let tStr = transpile(expression: target, locals: locals, isMethod: isMethod)
            let sStr = transpile(expression: start, locals: locals, isMethod: isMethod)
            let eStr = transpile(expression: end, locals: locals, isMethod: isMethod)
            return "\(tStr).getRange(start: \(sStr), end: \(eStr))"
        case .objPropIndex(let obj, let prop, let index, let index2):
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            let indexStr = transpile(expression: index, locals: locals, isMethod: isMethod)
            if let index2 {
                let index2Str = transpile(expression: index2, locals: locals, isMethod: isMethod)
                return "\(objStr).`\(prop)`.getRange(start: \(indexStr), end: \(index2Str))"
            }
            return "\(objStr).`\(prop)`[\(indexStr)]"
        case .chunkExpression(let type, let first, let last, let string, _):
            let stringStr = transpile(expression: string, locals: locals, isMethod: isMethod)
            let firstStr = transpile(expression: first, locals: locals, isMethod: isMethod)
            let lastStr = last.map { transpile(expression: $0, locals: locals, isMethod: isMethod) } ?? "nil"
            return "\(stringStr).chunk(\"\(type.lingoName)\", start: \(firstStr), end: \(lastStr))"
        case .lastStringChunk(let type, let obj):
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            return "\(objStr).lastChunk(\"\(type.lingoName)\")"
        case .stringChunkCount(let type, let obj):
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            return "\(objStr).chunkCount(\"\(type.lingoName)\")"
        case .spriteIntersects(let first, let second):
            let firstStr = transpile(expression: first, locals: locals, isMethod: isMethod)
            let secondStr = transpile(expression: second, locals: locals, isMethod: isMethod)
            return "LingoEnvironment.shared.callGlobal(\"intersects\", args: [\(firstStr), \(secondStr)])"
        case .spriteWithin(let first, let second):
            let firstStr = transpile(expression: first, locals: locals, isMethod: isMethod)
            let secondStr = transpile(expression: second, locals: locals, isMethod: isMethod)
            return "LingoEnvironment.shared.callGlobal(\"within\", args: [\(firstStr), \(secondStr)])"
        case .menuProp(let menuId, let prop):
            let menuStr = transpile(expression: menuId, locals: locals, isMethod: isMethod)
            return "LingoEnvironment.shared.callGlobal(\"menu\", args: [\(menuStr)]).`\(prop)`"
        case .menuItemProp(let menuId, let itemId, let prop):
            let menuStr = transpile(expression: menuId, locals: locals, isMethod: isMethod)
            let itemStr = transpile(expression: itemId, locals: locals, isMethod: isMethod)
            return "LingoEnvironment.shared.callGlobal(\"menuItem\", args: [\(itemStr), \(menuStr)]).`\(prop)`"
        case .soundProp(let soundId, let prop):
            let soundStr = transpile(expression: soundId, locals: locals, isMethod: isMethod)
            return "LingoEnvironment.shared.callGlobal(\"sound\", args: [\(soundStr)]).`\(prop)`"
        case .spriteProp(let spriteId, let prop):
            let spriteStr = transpile(expression: spriteId, locals: locals, isMethod: isMethod)
            return "LingoEnvironment.shared.callGlobal(\"sprite\", args: [\(spriteStr)]).`\(prop)`"
        case .member(let type, let id, _):
            let idStr = transpile(expression: id, locals: locals, isMethod: isMethod)
            let functionName = type.lowercased() == "sprite" ? "sprite" : "member"
            return isMethod ? "self.`\(functionName)`(\(idStr))" : "LingoEnvironment.shared.callGlobal(\"\(functionName)\", args: [\(idStr)])"
        case .newObj(let type, let args):
            let argsStr = transpile(expression: args, locals: locals, isMethod: isMethod)
            return isMethod ? "self.`new`(.string(\"\(type)\"), \(argsStr))" : "LingoEnvironment.shared.callGlobal(\"new\", args: [.string(\"\(type)\"), \(argsStr)])"
        case .range(let start, let end):
            let s = transpile(expression: start, locals: locals, isMethod: isMethod)
            let e = transpile(expression: end, locals: locals, isMethod: isMethod)
            return "LingoRange(\(s), \(e))"
        default:
            return ".void /* Unsupported expression: \(expression) */"
        }
    }

    private func formatClassName(_ relativePath: String) -> String {
        let name = relativePath.replacingOccurrences(of: ".ls", with: "")
        let components = name.split { !$0.isLetter && !$0.isNumber }
        return components.map { $0.prefix(1).uppercased() + String($0.dropFirst()).lowercased() }.joined()
    }

    /// Returns the maximum nesting depth of expressions within a statement,
    /// capped at `limit` to avoid spending time on deeply recursive trees.
    private func expressionDepth(of statement: Statement, limit: Int = 9) -> Int {
        switch statement {
        case .returnStatement(let e):
            return e.map { expressionDepth(of: $0, limit: limit) } ?? 0
        case .assignment(let t, let v, _):
            return max(expressionDepth(of: t, limit: limit), expressionDepth(of: v, limit: limit))
        case .put(_, let v, let t):
            let td = t.map { expressionDepth(of: $0, limit: limit) } ?? 0
            return max(expressionDepth(of: v, limit: limit), td)
        default:
            return 0
        }
    }

    private func expressionDepth(of expr: LingoAST.Expression, limit: Int = 9) -> Int {
        guard limit > 0 else { return limit }
        switch expr {
        case .binaryOperation(let l, _, let r):
            let ld = expressionDepth(of: l, limit: limit - 1)
            if ld >= limit { return limit }
            return max(ld, expressionDepth(of: r, limit: limit - 1)) + 1
        case .unaryOperation(_, let o):
            return expressionDepth(of: o, limit: limit - 1) + 1
        default:
            return 1
        }
    }

    private func escapeSwiftString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

private extension LingoAST.Expression {
    var isMeReference: Bool {
        if case .identifier(let name) = self {
            return name.lowercased() == "me"
        }
        return false
    }
}

private extension ChunkType {
    var lingoName: String {
        switch self {
        case .char: return "char"
        case .word: return "word"
        case .item: return "item"
        case .line: return "line"
        case .paragraph: return "paragraph"
        }
    }
}
