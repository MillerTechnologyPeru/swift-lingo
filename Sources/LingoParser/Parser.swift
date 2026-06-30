
import LingoAST
import LingoLexer

public class Parser {
    private let tokens: [Token]
    private var currentIndex: Int = 0
    
    public init(tokens: [Token]) {
        self.tokens = tokens
    }
    
    private var isAtEnd: Bool {
        return peek() == .eof
    }
    
    private func peek() -> Token {
        if currentIndex < tokens.count {
            return tokens[currentIndex]
        }
        return .eof
    }
    
    private func advance() -> Token {
        if !isAtEnd {
            currentIndex += 1
        }
        return previous()
    }
    
    private func previous() -> Token {
        return tokens[currentIndex - 1]
    }
    
    private func match(_ types: Token...) -> Bool {
        for type in types {
            if check(type) {
                _ = advance()
                return true
            }
        }
        return false
    }
    
    private func check(_ type: Token) -> Bool {
        if isAtEnd { return false }
        return peek() == type
    }
    
    // Case-insensitive check for identifier (which acts as keywords in our Lexer)
    private func matchKeyword(_ word: String) -> Bool {
        if isAtEnd { return false }
        if case .identifier(let id) = peek(), id.lowercased() == word.lowercased() {
            _ = advance()
            return true
        }
        return false
    }
    
    private func skipNewlines() {
        while check(.newline) {
            _ = advance()
        }
    }
    
    public func parseScript() -> Script {
        var statements: [Statement] = []
        
        skipNewlines()
        while !isAtEnd {
            if let stmt = parseTopLevel() {
                statements.append(stmt)
            }
            skipNewlines()
        }
        
        return Script(statements: statements)
    }
    
    private func parseTopLevel() -> Statement? {
        if matchKeyword("on") {
            return parseHandler()
        } else if matchKeyword("property") {
            var names: [String] = []
            repeat {
                if case .identifier(let name) = advance() {
                    names.append(name)
                }
            } while match(.comma)
            return .property(names: names)
        } else if matchKeyword("global") {
            var names: [String] = []
            repeat {
                if case .identifier(let name) = advance() {
                    names.append(name)
                }
            } while match(.comma)
            return .global(names: names)
        } else {
            // Might be a top-level statement or error
            return parseStatement()
        }
    }
    
    private func parseHandler() -> Statement? {
        // 'on' already matched
        guard case .identifier(let name) = advance() else { return nil }
        
        var arguments: [String] = []
        // arguments can be separated by spaces or commas
        while !check(.newline) && !isAtEnd {
            _ = match(.comma) // optional comma
            if case .identifier(let argName) = advance() {
                arguments.append(argName)
            } else {
                break
            }
        }
        
        var body: [Statement] = []
        while !isAtEnd {
            skipNewlines()
            if matchKeyword("end") {
                // optionally could have 'end handlerName' or 'end if' etc. but here we just match 'end'
                if case .identifier(let endName) = peek() {
                    if endName.lowercased() == name.lowercased() {
                        _ = advance() // consume optional name
                    }
                }
                break
            }
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        
        return .handler(name: name, arguments: arguments, body: body)
    }
    
    private func parseStatement() -> Statement? {
        if matchKeyword("if") {
            return parseIf()
        } else if matchKeyword("repeat") {
            return parseRepeat()
        } else if matchKeyword("return") {
            let expr = check(.newline) ? nil : parseExpression()
            return .returnStatement(expr)
        } else if matchKeyword("exit") {
            if matchKeyword("repeat") {
                return .exitRepeat
            }
            return .exit
        } else if matchKeyword("next") {
            if matchKeyword("repeat") {
                return .nextRepeat
            }
        } else if matchKeyword("case") {
            return parseCase()
        } else if matchKeyword("set") {
            // set x = y OR set x to y
            guard let target = parseExpression() else { return nil }
            
            if case .binaryOperation(let left, let op, let right) = target, op == .equals {
                return .assignment(target: left, value: right)
            }
            
            if match(.equals) || matchKeyword("to") {
                if let value = parseExpression() {
                    return .assignment(target: target, value: value)
                }
            }
        } else if matchKeyword("put") {
            guard let value = parseExpression() else { return nil }
            if matchKeyword("into") {
                if let target = parseExpression() {
                    return .put(type: .into, value: value, target: target)
                }
            } else if matchKeyword("after") {
                if let target = parseExpression() {
                    return .put(type: .after, value: value, target: target)
                }
            } else if matchKeyword("before") {
                if let target = parseExpression() {
                    return .put(type: .before, value: value, target: target)
                }
            }
        } else if matchKeyword("delete") {
             // simplified delete support
             guard let target = parseExpression() else { return nil }
             return .chunkDelete(chunk: target) 
        } else if matchKeyword("hilite") {
             guard let target = parseExpression() else { return nil }
             return .chunkHilite(chunk: target)
        } else if matchKeyword("tell") {
            guard let window = parseExpression() else { return nil }
            var body: [Statement] = []
            while !isAtEnd {
                skipNewlines()
                if matchKeyword("end") {
                    _ = matchKeyword("tell")
                    break
                }
                if let stmt = parseStatement() {
                    body.append(stmt)
                }
            }
            return .tell(window: window, body: body)
        } else if matchKeyword("play") {
            let args = check(.newline) ? nil : parseExpression()
            return .playCmd(args: args)
        } else if matchKeyword("sound") {
            if case .identifier(let cmd) = peek() {
                _ = advance()
                let args = check(.newline) ? nil : parseExpression()
                return .soundCmd(cmd: cmd, args: args)
            }
        } else if matchKeyword("when") {
            if case .identifier(let eventName) = advance() {
                _ = matchKeyword("then")
                if case .identifier(let scriptName) = peek() {
                    _ = advance()
                    return .when(event: eventName, script: scriptName)
                }
            }
        }
        
        // Otherwise, probably an assignment (x = y) or expression (foo())
        if let expr = parseExpression() {
            if case .binaryOperation(let left, let op, let right) = expr, op == .equals {
                return .assignment(target: left, value: right)
            }
            return .expressionStatement(expr)
        }
        
        _ = advance() // skip unrecognized
        return nil
    }
    
    private func parseIf() -> Statement? {
        guard let condition = parseExpression() else { return nil }
        _ = matchKeyword("then") // optional 'then'
        
        var body: [Statement] = []
        var elseBody: [Statement]? = nil
        
        // Single line if
        if !check(.newline) && !isAtEnd && !matchKeyword("end") && !matchKeyword("else") {
             if let stmt = parseStatement() {
                 body.append(stmt)
             }
             return .ifStatement(condition: condition, body: body, elseBody: elseBody)
        }

        while !isAtEnd {
            skipNewlines()
            if matchKeyword("end") {
                _ = matchKeyword("if") // optional 'if'
                break
            } else if matchKeyword("else") {
                skipNewlines()
                elseBody = []
                while !isAtEnd {
                    skipNewlines()
                    if matchKeyword("end") {
                        _ = matchKeyword("if")
                        break
                    }
                    if let stmt = parseStatement() {
                        elseBody?.append(stmt)
                    }
                }
                break
            }
            
            if let stmt = parseStatement() {
                body.append(stmt)
            }
        }
        
        return .ifStatement(condition: condition, body: body, elseBody: elseBody)
    }
    
    private func parseRepeat() -> Statement? {
        if matchKeyword("with") {
            guard case .identifier(let varName) = advance() else { return nil }
            _ = match(.equals)
            guard let startExpr = parseExpression() else { return nil }
            
            if matchKeyword("to") || matchKeyword("down") {
                _ = matchKeyword("to") // handles 'down to'
                guard let endExpr = parseExpression() else { return nil }
                
                var body: [Statement] = []
                while !isAtEnd {
                    skipNewlines()
                    if matchKeyword("end") {
                        _ = matchKeyword("repeat")
                        break
                    }
                    if let stmt = parseStatement() {
                        body.append(stmt)
                    }
                }
                return .repeatWithCounter(variable: varName, start: startExpr, end: endExpr, body: body, up: true)
            } else if matchKeyword("in") {
                // repeat with x in list
                guard let listExpr = parseExpression() else { return nil }
                var body: [Statement] = []
                while !isAtEnd {
                    skipNewlines()
                    if matchKeyword("end") {
                        _ = matchKeyword("repeat")
                        break
                    }
                    if let stmt = parseStatement() {
                        body.append(stmt)
                    }
                }
                return .repeatWithIn(variable: varName, list: listExpr, body: body)
            }
        } else if matchKeyword("while") {
            guard let condition = parseExpression() else { return nil }
            var body: [Statement] = []
            while !isAtEnd {
                skipNewlines()
                if matchKeyword("end") {
                    _ = matchKeyword("repeat")
                    break
                }
                if let stmt = parseStatement() {
                    body.append(stmt)
                }
            }
            return .repeatWhile(condition: condition, body: body)
        }
        return nil
    }
    
    private func parseCase() -> Statement? {
         guard let condition = parseExpression() else { return nil }
         _ = matchKeyword("of")
         
         var cases: [CaseBlock] = []
         var otherwise: [Statement]? = nil
         
         while !isAtEnd {
             skipNewlines()
             if matchKeyword("end") {
                 _ = matchKeyword("case")
                 break
             } else if matchKeyword("otherwise") {
                 _ = match(.colon)
                 otherwise = []
                 while !isAtEnd {
                     skipNewlines()
                     if matchKeyword("end") {
                         _ = matchKeyword("case")
                         break
                     }
                     if let stmt = parseStatement() {
                         otherwise?.append(stmt)
                     }
                 }
                 break
             } else {
                 // case value:
                 guard let val = parseExpression() else { break }
                 _ = match(.colon)
                 var body: [Statement] = []
                 while !isAtEnd {
                     skipNewlines()
                     if check(.identifier("")) || check(.number(0)) || check(.string("")) || check(.symbol("")) {
                         // Next case starts, though Lingo 'case' is loose. We'll break if we see another case literal or end/otherwise.
                         // This is a naive check. A better approach checks if the next line is a simple expression followed by a colon.
                         let peek1 = peek()
                         if case .identifier(let id) = peek1 {
                              if id.lowercased() == "end" || id.lowercased() == "otherwise" { break }
                         }
                         // Actually, in Lingo, case statements can be tricky. We just assume single statements or explicit ends.
                     }
                     
                     if matchKeyword("end") {
                         _ = matchKeyword("case")
                         return .caseStatement(condition: condition, cases: cases, otherwise: otherwise) // early exit hack for now
                     }
                     
                     if let stmt = parseStatement() {
                         body.append(stmt)
                     } else {
                         break
                     }
                 }
                 cases.append(CaseBlock(values: [val], body: body))
             }
         }
         return .caseStatement(condition: condition, cases: cases, otherwise: otherwise)
    }

    // Simplified Pratt parser for expressions
    private func parseExpression() -> Expression? {
        return parseBinaryExpression(precedence: 0)
    }
    
    private func parseBinaryExpression(precedence: Int) -> Expression? {
        var left = parsePrimary()
        guard left != nil else { return nil }
        
        while !isAtEnd {
            let opToken = peek()
            let opPrecedence = getPrecedence(opToken)
            if opPrecedence == 0 || opPrecedence < precedence {
                break
            }
            
            _ = advance()
            let op = getBinaryOperator(opToken)!
            
            if let right = parseBinaryExpression(precedence: opPrecedence) {
                left = .binaryOperation(left: left!, operator: op, right: right)
            }
        }
        
        return left
    }
    
    private func getPrecedence(_ token: Token) -> Int {
        switch token {
        case .equals, .notEquals, .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
            return 1
        case .concat, .concatSpace:
            return 2
        case .plus, .minus:
            return 3
        case .multiply, .divide:
            return 4
        case .identifier(let id):
            let lower = id.lowercased()
            if lower == "and" || lower == "or" { return 1 }
            if lower == "mod" { return 4 }
            return 0
        default:
            return 0
        }
    }
    
    private func getBinaryOperator(_ token: Token) -> BinaryOperator? {
        switch token {
        case .equals: return .equals
        case .notEquals: return .notEquals
        case .lessThan: return .lessThan
        case .greaterThan: return .greaterThan
        case .lessThanOrEqual: return .lessThanOrEqual
        case .greaterThanOrEqual: return .greaterThanOrEqual
        case .plus: return .add
        case .minus: return .subtract
        case .multiply: return .multiply
        case .divide: return .divide
        case .concat: return .stringConcat
        case .concatSpace: return .stringConcatSpace
        case .identifier(let id):
            let lower = id.lowercased()
            if lower == "and" { return .logicalAnd }
            if lower == "or" { return .logicalOr }
            if lower == "mod" { return .modulo }
            return nil
        default: return nil
        }
    }
    
    private func parsePrimary() -> Expression? {
        if match(.minus) {
            if let expr = parsePrimary() {
                return .unaryOperation(operator: .negate, operand: expr)
            }
        } else if matchKeyword("not") {
            if let expr = parsePrimary() {
                return .unaryOperation(operator: .not, operand: expr)
            }
        } else if matchKeyword("the") {
            if matchKeyword("last") {
                if matchKeyword("char") {
                    _ = matchKeyword("of")
                    if let target = parsePrimary() { return .lastStringChunk(type: .char, obj: target) }
                } else if matchKeyword("word") {
                    _ = matchKeyword("of")
                    if let target = parsePrimary() { return .lastStringChunk(type: .word, obj: target) }
                } else if matchKeyword("item") {
                    _ = matchKeyword("of")
                    if let target = parsePrimary() { return .lastStringChunk(type: .item, obj: target) }
                } else if matchKeyword("line") {
                    _ = matchKeyword("of")
                    if let target = parsePrimary() { return .lastStringChunk(type: .line, obj: target) }
                }
            } else if matchKeyword("number") {
                if matchKeyword("of") {
                    if matchKeyword("chars") {
                        _ = matchKeyword("in")
                        if let target = parsePrimary() { return .stringChunkCount(type: .char, obj: target) }
                    } else if matchKeyword("words") {
                        _ = matchKeyword("in")
                        if let target = parsePrimary() { return .stringChunkCount(type: .word, obj: target) }
                    } else if matchKeyword("items") {
                        _ = matchKeyword("in")
                        if let target = parsePrimary() { return .stringChunkCount(type: .item, obj: target) }
                    } else if matchKeyword("lines") {
                        _ = matchKeyword("in")
                        if let target = parsePrimary() { return .stringChunkCount(type: .line, obj: target) }
                    }
                }
            }
            
            if case .identifier(let prop) = advance() {
                if matchKeyword("of") {
                    if matchKeyword("menu") {
                        if let menuId = parsePrimary() {
                            return .menuProp(menuId: menuId, prop: prop)
                        }
                    } else if matchKeyword("menuItem") {
                        if let itemId = parsePrimary() {
                            _ = matchKeyword("of")
                            _ = matchKeyword("menu")
                            if let menuId = parsePrimary() {
                                return .menuItemProp(menuId: menuId, itemId: itemId, prop: prop)
                            }
                        }
                    } else if matchKeyword("sound") {
                        if let soundId = parsePrimary() {
                            return .soundProp(soundId: soundId, prop: prop)
                        }
                    } else if matchKeyword("sprite") {
                        if let spriteId = parsePrimary() {
                            return .spriteProp(spriteId: spriteId, prop: prop)
                        }
                    } else if let target = parsePrimary() {
                        return .theProp(obj: target, prop: prop)
                    }
                }
                return .the(prop)
            }
        } else if matchKeyword("sprite") {
            if let spriteId = parsePrimary() {
                if matchKeyword("intersects") {
                    if let target = parsePrimary() { return .spriteIntersects(first: spriteId, second: target) }
                } else if matchKeyword("within") {
                    if let target = parsePrimary() { return .spriteWithin(first: spriteId, second: target) }
                }
                return .member(type: "sprite", id: spriteId, castId: nil)
            }
        } else if matchKeyword("char") {
             return parseChunk(.char)
        } else if matchKeyword("word") {
             return parseChunk(.word)
        } else if matchKeyword("item") {
             return parseChunk(.item)
        } else if matchKeyword("line") {
             return parseChunk(.line)
        } else if match(.leftBracket) {
            // List or property list
            if match(.colon) {
                // empty prop list [:]
                _ = match(.rightBracket)
                return .propertyList([])
            }
            
            var items: [Expression] = []
            var isPropList = false
            var props: [PropertyListEntry] = []
            
            if match(.rightBracket) {
                return .list([]) // empty list
            }
            
            repeat {
                guard let expr = parseExpression() else { break }
                if match(.colon) {
                    isPropList = true
                    if let val = parseExpression() {
                        props.append(PropertyListEntry(key: expr, value: val))
                    }
                } else {
                    items.append(expr)
                }
            } while match(.comma)
            
            _ = match(.rightBracket)
            
            if isPropList { return .propertyList(props) }
            return .list(items)
        } else if match(.leftParen) {
            let expr = parseExpression()
            _ = match(.rightParen)
            return expr
        }
        
        let token = advance()
        var baseExpr: Expression? = nil
        
        switch token {
        case .integer(let i): baseExpr = .integer(i)
        case .number(let d): baseExpr = .float(d)
        case .string(let s): baseExpr = .string(s)
        case .symbol(let s): baseExpr = .symbol(s)
        case .identifier(let id):
            // Check if function call
            if match(.leftParen) {
                var args: [Expression] = []
                if !check(.rightParen) {
                    repeat {
                        if let arg = parseExpression() {
                            args.append(arg)
                        }
                    } while match(.comma)
                }
                _ = match(.rightParen)
                baseExpr = .functionCall(target: nil, name: id, arguments: args)
            } else {
                let lower = id.lowercased()
                if lower == "true" { baseExpr = .boolean(true) }
                else if lower == "false" { baseExpr = .boolean(false) }
                else if lower == "empty" { baseExpr = .string("") }
                else { baseExpr = .identifier(id) }
            }
        default: return nil
        }
        
        // Handle dot access, bracket access, and method calls
        while true {
            if match(.dot) {
                if case .identifier(let prop) = advance() {
                    if match(.leftParen) {
                        var args: [Expression] = []
                        if !check(.rightParen) {
                            repeat {
                                if let arg = parseExpression() {
                                    args.append(arg)
                                }
                            } while match(.comma)
                        }
                        _ = match(.rightParen)
                        baseExpr = .functionCall(target: baseExpr, name: prop, arguments: args)
                    } else {
                        baseExpr = .propertyAccess(target: baseExpr!, property: prop)
                    }
                }
            } else if match(.leftBracket) {
                if let index = parseExpression() {
                    _ = match(.rightBracket)
                    baseExpr = .elementAccess(target: baseExpr!, index: index)
                }
            } else {
                break
            }
        }
        
        return baseExpr
    }
    
    private func parseChunk(_ type: ChunkType) -> Expression? {
         // e.g. word 1 of Entry
         // char -30000 of record (negative index)
         guard let index = parsePrimary() else { return nil }
         if matchKeyword("to") {
             _ = parsePrimary() // Ignoring range for now, simplify AST
         }
         _ = matchKeyword("of")
         guard let target = parsePrimary() else { return nil }
         return .chunkExpression(type: type, first: index, last: nil, string: target)
    }
}
