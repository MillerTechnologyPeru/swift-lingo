import Foundation
import LingoAST
import LingoParser

public class LingoTranspiler {
    public init() {}
    
    public func transpile(script: Script, relativePath: String, originalPath: String) -> String {
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
            
            for prop in properties {
                output += "    public var `\(prop)`: LingoValue = .void\n"
            }
            if !properties.isEmpty { output += "\n" }
            
            output += "    public override func getProperty(_ name: String) -> LingoValue {\n"
            output += "        switch name.lowercased() {\n"
            for prop in properties {
                output += "        case \"\(prop.lowercased())\": return self.`\(prop)`\n"
            }
            output += "        default: return super.getProperty(name)\n"
            output += "        }\n"
            output += "    }\n\n"
            
            output += "    public override func setProperty(_ name: String, value: LingoValue) {\n"
            output += "        switch name.lowercased() {\n"
            for prop in properties {
                output += "        case \"\(prop.lowercased())\": self.`\(prop)` = value\n"
            }
            output += "        default: super.setProperty(name, value: value)\n"
            output += "        }\n"
            output += "    }\n\n"
            
            for stmt in script.statements {
                if case .handler(let name, let arguments, let body) = stmt {
                    output += transpileHandler(name: name, args: arguments, body: body, isMethod: true)
                }
            }
            
            output += "}\n"
        } else {
            for stmt in script.statements {
                if case .handler(let name, let arguments, let body) = stmt {
                    output += transpileHandler(name: name, args: arguments, body: body, isMethod: false)
                }
            }
        }
        
        return output
    }
    
    private func transpileHandler(name: String, args: [String], body: [Statement], isMethod: Bool) -> String {
        var output = ""
        let isInit = isMethod && name.lowercased() == "new"
        
        if isInit {
            output += "    public override init() {\n"
            output += "        super.init()\n"
        } else {
            let funcName = isMethod ? "`\(name)`" : "lingo_\(name)"
            let indent = isMethod ? "    " : ""
            output += "\(indent)public func \(funcName)("
            let swiftArgs = args.filter { $0.lowercased() != "me" }.map { "_ `\($0)`: LingoValue" }.joined(separator: ", ")
            output += "\(swiftArgs)) -> LingoValue {\n"
        }
        
        let indent = isMethod ? "        " : "    "
        
        var locals = Set<String>()
        var globals = Set<String>()
        collectVariables(in: body, locals: &locals, globals: &globals)
        for arg in args { locals.insert(arg.lowercased()) }
        locals.subtract(globals)
        
        let hoisted = locals.filter { !args.map{$0.lowercased()}.contains($0) }
        for variable in hoisted {
            output += "\(indent)var `\(variable)`: LingoValue = .void\n"
        }
        if !hoisted.isEmpty { output += "\n" }
        
        for stmt in body {
            output += transpile(statement: stmt, indent: indent, locals: locals, isMethod: isMethod)
        }
        
        if isInit {
            output += "    }\n\n"
        } else {
            output += "\(indent)return .void\n"
            let endIndent = isMethod ? "    " : ""
            output += "\(endIndent)}\n\n"
        }
        return output
    }
    
    private func collectVariables(in statements: [Statement], locals: inout Set<String>, globals: inout Set<String>) {
        for stmt in statements {
            switch stmt {
            case .global(let names):
                for name in names { globals.insert(name.lowercased()) }
            case .assignment(let target, _):
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
    
    private func transpile(statement: Statement, indent: String, locals: Set<String>, isMethod: Bool) -> String {
        var output = "\(indent)// \(statement.lingoString)\n"
        switch statement {
        case .global, .property:
            break
        case .handler:
            break
        case .assignment(let target, let value):
            let valStr = transpile(expression: value, locals: locals, isMethod: isMethod)
            if case .identifier(let name) = target {
                if locals.contains(name.lowercased()) {
                    output += "\(indent)`\(name.lowercased())` = \(valStr)\n"
                } else {
                    let prefix = isMethod ? "self." : "LingoEnvironment.shared."
                    output += "\(indent)\(prefix)`\(name)` = \(valStr)\n"
                }
            } else if case .propertyAccess(let obj, let prop) = target {
                let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
                output += "\(indent)\(objStr).setProperty(\"\(prop)\", value: \(valStr))\n"
            } else if case .elementAccess(let obj, let indexExpr) = target {
                let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
                let idxStr = transpile(expression: indexExpr, locals: locals, isMethod: isMethod)
                output += "\(indent)\(objStr).setElement(index: \(idxStr), value: \(valStr))\n"
            } else {
                let targetStr = transpile(expression: target, locals: locals, isMethod: isMethod)
                output += "\(indent)\(targetStr) = \(valStr)\n"
            }
        case .put(_, let value, let target):
            let valStr = transpile(expression: value, locals: locals, isMethod: isMethod)
            if let t = target {
                if case .identifier(let name) = t {
                    if locals.contains(name.lowercased()) {
                        output += "\(indent)`\(name.lowercased())` = \(valStr)\n"
                    } else {
                        let prefix = isMethod ? "self." : "LingoEnvironment.shared."
                        output += "\(indent)\(prefix)`\(name)` = \(valStr)\n"
                    }
                } else {
                    let targetStr = transpile(expression: t, locals: locals, isMethod: isMethod)
                    output += "\(indent)\(targetStr) = \(valStr)\n"
                }
            }
        case .ifStatement(let cond, let body, let elseBody):
            let condStr = transpile(expression: cond, locals: locals, isMethod: isMethod)
            output += "\(indent)if (\(condStr)).asBool() {\n"
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
            output += "\(indent)while (`\(variable.lowercased())` \(op) \(endStr)).asBool() {\n"
            for stmt in body {
                output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
            }
            output += "\(indent)    `\(variable.lowercased())` = `\(variable.lowercased())` \(inc) .integer(1)\n"
            output += "\(indent)}\n"
        case .repeatWhile(let cond, let body):
            let condStr = transpile(expression: cond, locals: locals, isMethod: isMethod)
            output += "\(indent)while (\(condStr)).asBool() {\n"
            for stmt in body {
                output += transpile(statement: stmt, indent: indent + "    ", locals: locals, isMethod: isMethod)
            }
            output += "\(indent)}\n"
        case .expressionStatement(let expr):
            let exprStr = transpile(expression: expr, locals: locals, isMethod: isMethod)
            output += "\(indent)_ = \(exprStr)\n"
        case .returnStatement(let expr):
            if let expr = expr {
                let exprStr = transpile(expression: expr, locals: locals, isMethod: isMethod)
                output += "\(indent)return \(exprStr)\n"
            } else {
                output += "\(indent)return .void\n"
            }
        case .exit:
            output += "\(indent)return .void\n"
        case .exitRepeat:
            output += "\(indent)break\n"
        case .nextRepeat:
            output += "\(indent)continue\n"
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
        default:
            output += "\(indent)// (Unsupported statement)\n"
        }
        return output
    }
    
    private func transpile(expression: LingoAST.Expression, locals: Set<String>, isMethod: Bool) -> String {
        switch expression {
        case .void: return ".void"
        case .integer(let v): return ".integer(\(v))"
        case .float(let v): return ".float(\(v))"
        case .string(let v): return ".string(\"\(v)\")"
        case .symbol(let v): return ".symbol(\"\(v)\")"
        case .boolean(let v): return ".integer(\(v ? 1 : 0))"
        case .identifier(let name):
            let lower = name.lowercased()
            if lower == "me" { return ".object(self)" }
            if locals.contains(lower) {
                return "`\(lower)`"
            } else {
                return isMethod ? "self.`\(name)`" : "LingoEnvironment.shared.getGlobal(\"\(name)\")"
            }
        case .the(let prop), .theProp(.void, let prop):
            return isMethod ? "self.`\(prop)`" : "LingoEnvironment.shared.getGlobal(\"\(prop)\")"
        case .theProp(let obj, let prop):
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            return "\(objStr).`\(prop)`"
        case .objProp(let obj, let prop):
            let objStr = transpile(expression: obj, locals: locals, isMethod: isMethod)
            return "\(objStr).`\(prop)`"
        case .propertyAccess(let target, let prop):
            let tStr = transpile(expression: target, locals: locals, isMethod: isMethod)
            return "\(tStr).`\(prop)`"
        case .functionCall(let target, let name, let args):
            let argStr = args.map { transpile(expression: $0, locals: locals, isMethod: isMethod) }.joined(separator: ", ")
            if let t = target {
                let tStr = transpile(expression: t, locals: locals, isMethod: isMethod)
                return "\(tStr).`\(name)`(\(argStr))"
            } else {
                if locals.contains(name.lowercased()) {
                    return "`\(name.lowercased())`(\(argStr))" // LingoValue being called
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
        case .binaryOperation(let left, let op, let right):
            let l = transpile(expression: left, locals: locals, isMethod: isMethod)
            let r = transpile(expression: right, locals: locals, isMethod: isMethod)
            switch op {
            case .equals: return "(\(l) == \(r))"
            case .notEquals: return "(\(l) != \(r))"
            case .logicalAnd: return "((\(l)).asBool() && (\(r)).asBool() ? LingoValue.integer(1) : LingoValue.integer(0))"
            case .logicalOr: return "((\(l)).asBool() || (\(r)).asBool() ? LingoValue.integer(1) : LingoValue.integer(0))"
            case .stringConcat, .stringConcatSpace: return "(\(l) + \(r))"
            case .modulo: return "(\(l) % \(r))"
            case .contains: return "\(l).contains(\(r))"
            case .starts: return "\(l).starts(with: \(r))"
            default: return "(\(l) \(op.rawValue) \(r))"
            }
        case .unaryOperation(let op, let operand):
            let opr = transpile(expression: operand, locals: locals, isMethod: isMethod)
            if op == .not {
                return "((\(opr)).asBool() ? LingoValue.integer(0) : LingoValue.integer(1))"
            }
            return "(\(op.rawValue)\(opr))"
        case .list(let items):
            let itemsStr = items.map { transpile(expression: $0, locals: locals, isMethod: isMethod) }.joined(separator: ", ")
            return ".list([\(itemsStr)])"
        case .propertyList(let entries):
            let entriesStr = entries.map { "(key: \(transpile(expression: $0.key, locals: locals, isMethod: isMethod)), value: \(transpile(expression: $0.value, locals: locals, isMethod: isMethod)))" }.joined(separator: ", ")
            return ".propertyList([\(entriesStr)])"
        case .elementAccess(let target, let index):
            let tStr = transpile(expression: target, locals: locals, isMethod: isMethod)
            let iStr = transpile(expression: index, locals: locals, isMethod: isMethod)
            return "\(tStr)[\(iStr)]"
        case .elementRangeAccess(let target, let start, let end):
            let tStr = transpile(expression: target, locals: locals, isMethod: isMethod)
            let sStr = transpile(expression: start, locals: locals, isMethod: isMethod)
            let eStr = transpile(expression: end, locals: locals, isMethod: isMethod)
            return "\(tStr).getRange(start: \(sStr), end: \(eStr))"
        case .member(_, let id, _):
            let idStr = transpile(expression: id, locals: locals, isMethod: isMethod)
            return isMethod ? "self.`member`(\(idStr))" : "LingoEnvironment.shared.callGlobal(\"member\", args: [\(idStr)])"
        case .newObj(let type, let args):
            let argsStr = transpile(expression: args, locals: locals, isMethod: isMethod)
            return isMethod ? "self.`new`(.string(\"\(type)\"), \(argsStr))" : "LingoEnvironment.shared.callGlobal(\"new\", args: [.string(\"\(type)\"), \(argsStr)])"
        default:
            return ".void /* Unsupported expression: \(expression) */"
        }
    }
    
    private func formatClassName(_ relativePath: String) -> String {
        let name = relativePath.replacingOccurrences(of: ".ls", with: "")
        let components = name.split { !$0.isLetter && !$0.isNumber }
        return components.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
    }
}
