public enum Token: Equatable {
    case identifier(String)
    case number(Double)
    case integer(Int)
    case string(String)
    case symbol(String) // e.g. #PREGAME
    
    // Punctuation
    case leftParen
    case rightParen
    case leftBracket
    case rightBracket
    case colon
    case comma
    case dot
    case range // ..
    
    // Operators
    case plus
    case minus
    case multiply
    case divide
    case equals
    case lessThan
    case greaterThan
    case lessThanOrEqual
    case greaterThanOrEqual
    case notEquals
    case concat       // &
    case concatSpace  // &&
    
    // Control
    case newline
    case eof
}
