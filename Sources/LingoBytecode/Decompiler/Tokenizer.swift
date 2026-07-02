/// Token categories for syntax-highlighting decompiled Lingo source.
enum TokenType: Equatable {
    case keyword  // if, then, else, end, repeat, put, set, the, of, etc.
    case identifier  // variable and function names
    case number  // integers and floats
    case string  // "quoted strings"
    case symbol  // #symbols
    case `operator`  // +, -, *, /, &, =, <>, etc.
    case comment  // -- comments
    case builtin  // built-in properties/functions (the xxx)
    case punctuation  // ( ) [ ] , :
    case whitespace  // spaces
}

/// A span of text tagged with its token type.
struct Span: Equatable {
    var text: String
    var tokenType: TokenType
}

/// Keywords in Lingo (case-insensitive).
private let keywords: Set<String> = [
    "if", "then", "else", "end", "repeat", "while", "with", "in", "to", "down",
    "exit", "return", "next", "put", "into", "before", "after", "set",
    "global", "property", "on", "me", "new", "case", "of", "otherwise",
    "tell", "and", "or", "not", "mod", "true", "false", "void",
    "sprite", "member", "castlib", "field", "the",
    "char", "word", "line", "item"
]

private func isKeyword(_ word: String) -> Bool {
    keywords.contains(word.lowercased())
}

extension Character {
    /// Matches Lingo source's own ASCII digits only, not every Unicode
    /// codepoint `Character.isNumber` would otherwise accept.
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

/// Tokenizes one line of decompiled Lingo source into spans for syntax
/// highlighting. Operates line-by-line (matching how the decompiler already
/// produces output one statement/line at a time) rather than on a whole
/// script, so a `--` comment always runs to the end of what it's given.
func tokenizeLine(_ line: String) -> [Span] {
    var spans: [Span] = []
    let chars = Array(line)
    var pos = 0

    while pos < chars.count {
        let ch = chars[pos]

        // Comment (-- to end of line)
        if ch == "-", pos + 1 < chars.count, chars[pos + 1] == "-" {
            spans.append(Span(text: String(chars[pos...]), tokenType: .comment))
            break
        }

        // Whitespace
        if ch.isWhitespace {
            let start = pos
            while pos < chars.count, chars[pos].isWhitespace {
                pos += 1
            }
            spans.append(Span(text: String(chars[start..<pos]), tokenType: .whitespace))
            continue
        }

        // String literal
        if ch == "\"" {
            let start = pos
            pos += 1
            while pos < chars.count, chars[pos] != "\"" {
                pos += 1
            }
            if pos < chars.count {
                pos += 1  // include closing quote
            }
            spans.append(Span(text: String(chars[start..<pos]), tokenType: .string))
            continue
        }

        // Symbol (#identifier)
        if ch == "#" {
            let start = pos
            pos += 1
            while pos < chars.count, chars[pos].isLetter || chars[pos].isNumber || chars[pos] == "_" {
                pos += 1
            }
            spans.append(Span(text: String(chars[start..<pos]), tokenType: .symbol))
            continue
        }

        // Number (including negative numbers and floats)
        if ch.isASCIIDigit || (ch == "-" && pos + 1 < chars.count && chars[pos + 1].isASCIIDigit) {
            let start = pos
            if ch == "-" {
                pos += 1
            }
            while pos < chars.count, chars[pos].isASCIIDigit {
                pos += 1
            }
            // Decimal point
            if pos < chars.count, chars[pos] == ".", pos + 1 < chars.count, chars[pos + 1].isASCIIDigit {
                pos += 1
                while pos < chars.count, chars[pos].isASCIIDigit {
                    pos += 1
                }
            }
            // Exponent
            if pos < chars.count, chars[pos] == "e" || chars[pos] == "E" {
                let expStart = pos
                pos += 1
                if pos < chars.count, chars[pos] == "+" || chars[pos] == "-" {
                    pos += 1
                }
                if pos < chars.count, chars[pos].isASCIIDigit {
                    while pos < chars.count, chars[pos].isASCIIDigit {
                        pos += 1
                    }
                } else {
                    pos = expStart  // not a valid exponent, backtrack
                }
            }
            spans.append(Span(text: String(chars[start..<pos]), tokenType: .number))
            continue
        }

        // Identifier or keyword
        if ch.isLetter || ch == "_" {
            let start = pos
            while pos < chars.count, chars[pos].isLetter || chars[pos].isNumber || chars[pos] == "_" {
                pos += 1
            }
            let word = String(chars[start..<pos])
            spans.append(Span(text: word, tokenType: isKeyword(word) ? .keyword : .identifier))
            continue
        }

        // Multi-character operators
        if pos + 1 < chars.count {
            let twoChar = String(chars[pos...(pos + 1)])
            if ["<>", "<=", ">=", "&&"].contains(twoChar) {
                spans.append(Span(text: twoChar, tokenType: .operator))
                pos += 2
                continue
            }
        }

        // Single-character operators
        if "+-*/&=<>.".contains(ch) {
            spans.append(Span(text: String(ch), tokenType: .operator))
            pos += 1
            continue
        }

        // Punctuation
        if "()[],:".contains(ch) {
            spans.append(Span(text: String(ch), tokenType: .punctuation))
            pos += 1
            continue
        }

        // Unknown character - treat as identifier
        spans.append(Span(text: String(ch), tokenType: .identifier))
        pos += 1
    }

    return spans
}
