

public struct Lexer {
    public let input: String
    private var currentIndex: String.Index
    
    public init(input: String) {
        self.input = input
        self.currentIndex = input.startIndex
    }
    
    public mutating func tokenize() -> [Token] {
        var tokens: [Token] = []
        
        while currentIndex < input.endIndex {
            let char = input[currentIndex]
            
            if char.isWhitespace && !char.isNewline {
                advance()
                continue
            }
            
            if char.isNewline {
                tokens.append(.newline)
                advance()
                continue
            }
            
            if char == "\\" {
                // line continuation: skip the backslash and the following newline
                advance()
                skipWhitespace(includingNewlines: true)
                continue
            }
            
            if char == "-" {
                let nextIndex = input.index(after: currentIndex)
                if nextIndex < input.endIndex && input[nextIndex] == "-" {
                    // Comment, skip to end of line
                    skipComment()
                    continue
                }
                tokens.append(.minus)
                advance()
                continue
            }
            
            if char == "<" {
                advance()
                if currentIndex < input.endIndex && input[currentIndex] == "=" {
                    tokens.append(.lessThanOrEqual)
                    advance()
                } else if currentIndex < input.endIndex && input[currentIndex] == ">" {
                    tokens.append(.notEquals)
                    advance()
                } else {
                    tokens.append(.lessThan)
                }
                continue
            }
            
            if char == ">" {
                advance()
                if currentIndex < input.endIndex && input[currentIndex] == "=" {
                    tokens.append(.greaterThanOrEqual)
                    advance()
                } else {
                    tokens.append(.greaterThan)
                }
                continue
            }
            
            if char == "&" {
                advance()
                if currentIndex < input.endIndex && input[currentIndex] == "&" {
                    tokens.append(.concatSpace)
                    advance()
                } else {
                    tokens.append(.concat)
                }
                continue
            }
            
            if char.isLetter || char == "_" {
                tokens.append(lexIdentifierOrKeyword())
                continue
            }
            
            if char.isNumber {
                tokens.append(lexNumber())
                continue
            }
            
            if char == "\"" {
                tokens.append(lexString())
                continue
            }
            
            if char == "#" {
                tokens.append(lexSymbol())
                continue
            }
            
            switch char {
            case "(": tokens.append(.leftParen); advance()
            case ")": tokens.append(.rightParen); advance()
            case "[": tokens.append(.leftBracket); advance()
            case "]": tokens.append(.rightBracket); advance()
            case ":": tokens.append(.colon); advance()
            case ",": tokens.append(.comma); advance()
            case ".": tokens.append(.dot); advance()
            case "+": tokens.append(.plus); advance()
            case "*": tokens.append(.multiply); advance()
            case "/": tokens.append(.divide); advance()
            case "=": tokens.append(.equals); advance()
            default:
                // Unrecognized character, just advance for now or throw error
                advance()
            }
        }
        
        tokens.append(.eof)
        return tokens
    }
    
    private mutating func advance() {
        if currentIndex < input.endIndex {
            currentIndex = input.index(after: currentIndex)
        }
    }
    
    private mutating func skipWhitespace(includingNewlines: Bool) {
        while currentIndex < input.endIndex {
            let char = input[currentIndex]
            if char.isWhitespace {
                if char.isNewline && !includingNewlines {
                    break
                }
                advance()
            } else {
                break
            }
        }
    }
    
    private mutating func skipComment() {
        while currentIndex < input.endIndex && !input[currentIndex].isNewline {
            advance()
        }
    }
    
    private mutating func lexIdentifierOrKeyword() -> Token {
        var str = ""
        while currentIndex < input.endIndex {
            let char = input[currentIndex]
            if char.isLetter || char.isNumber || char == "_" {
                str.append(char)
                advance()
            } else {
                break
            }
        }
        return .identifier(str)
    }
    
    private mutating func lexNumber() -> Token {
        var str = ""
        var hasDot = false
        while currentIndex < input.endIndex {
            let char = input[currentIndex]
            if char.isNumber {
                str.append(char)
                advance()
            } else if char == "." && !hasDot {
                let nextIndex = input.index(after: currentIndex)
                if nextIndex < input.endIndex && input[nextIndex].isNumber {
                    hasDot = true
                    str.append(char)
                    advance()
                } else {
                    break // It's a dot operator, not a decimal point
                }
            } else {
                break
            }
        }
        if hasDot {
            return .number(Double(str) ?? 0.0)
        } else {
            return .integer(Int(str) ?? 0)
        }
    }
    
    private mutating func lexString() -> Token {
        advance() // Skip opening quote
        var str = ""
        while currentIndex < input.endIndex && input[currentIndex] != "\"" {
            if input[currentIndex] == "\\" {
                advance()
                if currentIndex < input.endIndex {
                    // simple escape handling
                    str.append(input[currentIndex])
                    advance()
                }
            } else {
                str.append(input[currentIndex])
                advance()
            }
        }
        if currentIndex < input.endIndex {
            advance() // Skip closing quote
        }
        return .string(str)
    }
    
    private mutating func lexSymbol() -> Token {
        advance() // Skip #
        var str = ""
        while currentIndex < input.endIndex {
            let char = input[currentIndex]
            if char.isLetter || char.isNumber || char == "_" {
                str.append(char)
                advance()
            } else {
                break
            }
        }
        return .symbol(str)
    }
}
