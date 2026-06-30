import Foundation
import LingoAST
import LingoParser

public class LingoTranspiler {
    public init() {}
    
    public func transpile(script: Script, fileName: String, originalPath: String) -> String {
        var output = "// Transpiled from \(originalPath)\n"
        output += "import LingoRuntime\n\n"
        
        let isParent = fileName.lowercased().hasPrefix("parent_")
        let isBehavior = fileName.lowercased().hasPrefix("behavior_")
        
        if isParent || isBehavior {
            let className = formatClassName(fileName)
            output += "public class \(className): LingoObject {\n"
            
            // Collect properties
            var properties: [String] = []
            for stmt in script.statements {
                if case .property(let names) = stmt {
                    properties.append(contentsOf: names)
                }
            }
            
            for prop in properties {
                output += "    public var \(prop): LingoValue = .void\n"
            }
            if !properties.isEmpty { output += "\n" }
            
            // Convert properties to override get/set
            output += "    public override func getProperty(_ name: String) -> LingoValue {\n"
            output += "        switch name.lowercased() {\n"
            for prop in properties {
                output += "        case \"\(prop.lowercased())\": return \(prop)\n"
            }
            output += "        default: return super.getProperty(name)\n"
            output += "        }\n"
            output += "    }\n\n"
            
            output += "    public override func setProperty(_ name: String, value: LingoValue) {\n"
            output += "        switch name.lowercased() {\n"
            for prop in properties {
                output += "        case \"\(prop.lowercased())\": \(prop) = value\n"
            }
            output += "        default: super.setProperty(name, value: value)\n"
            output += "        }\n"
            output += "    }\n\n"
            
            // Handlers
            for stmt in script.statements {
                if case .handler(let name, let arguments, let body) = stmt {
                    output += transpileHandler(name: name, args: arguments, body: body, isMethod: true)
                }
            }
            
            output += "}\n"
        } else {
            // Movie script (global)
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
            let funcName = isMethod ? name : "lingo_\(name)"
            let indent = isMethod ? "    " : ""
            output += "\(indent)public func \(funcName)("
            let swiftArgs = args.filter { $0.lowercased() != "me" }.map { "_ \($0): LingoValue" }.joined(separator: ", ")
            output += "\(swiftArgs)) -> LingoValue {\n"
        }
        
        let indent = isMethod ? "        " : "    "
        output += "\(indent)// TODO: Body transpilation\n"
        
        if isInit {
            output += "    }\n\n"
        } else {
            output += "\(indent)return .void\n"
            let endIndent = isMethod ? "    " : ""
            output += "\(endIndent)}\n\n"
        }
        return output
    }
    
    private func formatClassName(_ fileName: String) -> String {
        let name = fileName.replacingOccurrences(of: ".ls", with: "")
        let components = name.split { !$0.isLetter && !$0.isNumber }
        return components.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
    }
}
