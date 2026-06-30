public struct Script: Equatable {
    public var statements: [Statement]
    
    public init(statements: [Statement]) {
        self.statements = statements
    }
}

public enum Statement: Equatable {
    case global(names: [String])
    case property(names: [String])
    case handler(name: String, arguments: [String], body: [Statement])
    case assignment(target: Expression, value: Expression)
    case putInto(value: Expression, target: Expression)
    case ifStatement(condition: Expression, body: [Statement], elseBody: [Statement]?)
    case repeatWithCounter(variable: String, start: Expression, end: Expression, body: [Statement])
    case repeatWhile(condition: Expression, body: [Statement])
    case repeatWithIn(variable: String, list: Expression, body: [Statement])
    case expressionStatement(Expression)
    case returnStatement(Expression?)
    case exitStatement
    case nextRepeat
    case caseStatement(condition: Expression, cases: [CaseBlock], otherwise: [Statement]?)
}

public struct CaseBlock: Equatable {
    public var values: [Expression]
    public var body: [Statement]
    
    public init(values: [Expression], body: [Statement]) {
        self.values = values
        self.body = body
    }
}

public indirect enum Expression: Equatable {
    case integer(Int)
    case float(Double)
    case string(String)
    case symbol(String) // e.g. #PREGAME
    case boolean(Bool)
    
    case identifier(String)
    case propertyAccess(target: Expression, property: String) // object.property or the property of object
    case elementAccess(target: Expression, index: Expression) // array[index]
    
    case list([Expression]) // [1, 2, 3]
    case propertyList([PropertyListEntry]) // [#key: value]
    
    case functionCall(target: Expression?, name: String, arguments: [Expression]) // obj.method(args) or function(args)
    
    case binaryOperation(left: Expression, operator: BinaryOperator, right: Expression)
    case unaryOperation(operator: UnaryOperator, operand: Expression)
    
    case chunkExpression(type: ChunkType, index: Expression, target: Expression) // e.g. word 1 of Entry
}

public struct PropertyListEntry: Equatable {
    public var key: Expression
    public var value: Expression
    
    public init(key: Expression, value: Expression) {
        self.key = key
        self.value = value
    }
}

public enum ChunkType: Equatable {
    case char
    case word
    case item
    case line
}

public enum BinaryOperator: String, Equatable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "mod"
    case equals = "="
    case notEquals = "<>"
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case logicalAnd = "and"
    case logicalOr = "or"
    case stringConcat = "&"
    case stringConcatSpace = "&&"
}

public enum UnaryOperator: String, Equatable {
    case negate = "-"
    case not = "not"
}
