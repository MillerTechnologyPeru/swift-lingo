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
    case put(type: PutType, value: Expression, target: Expression?)
    case ifStatement(condition: Expression, body: [Statement], elseBody: [Statement]?)
    case repeatWithCounter(variable: String, start: Expression, end: Expression, body: [Statement], up: Bool)
    case repeatWhile(condition: Expression, body: [Statement])
    case repeatWithIn(variable: String, list: Expression, body: [Statement])
    case expressionStatement(Expression)
    case returnStatement(Expression?)
    case exit
    case exitRepeat
    case nextRepeat
    case caseStatement(condition: Expression, cases: [CaseBlock], otherwise: [Statement]?)
    case tell(window: Expression, body: [Statement])
    case when(event: String, script: String)
    case soundCmd(cmd: String, args: Expression?)
    case playCmd(args: Expression?)
    case chunkHilite(chunk: Expression)
    case chunkDelete(chunk: Expression)
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
    case void
    case integer(Int)
    case float(Double)
    case string(String)
    case symbol(String) // e.g. #PREGAME
    case boolean(Bool)
    
    case identifier(String)
    case the(String)
    case theProp(obj: Expression, prop: String)
    case objProp(obj: Expression, prop: String)
    case propertyAccess(target: Expression, property: String) // object.property or the property of object
    case elementAccess(target: Expression, index: Expression) // array[index]
    case objPropIndex(obj: Expression, prop: String, index: Expression, index2: Expression?)
    
    case list([Expression]) // [1, 2, 3]
    case propertyList([PropertyListEntry]) // [#key: value]
    case argList([Expression])
    case argListNoRet([Expression])
    
    case functionCall(target: Expression?, name: String, arguments: [Expression]) // obj.method(args) or function(args)
    case call(name: String, args: Expression)
    case objCall(name: String, args: Expression)
    case objCallV4(obj: Expression, args: Expression)
    
    case binaryOperation(left: Expression, operator: BinaryOperator, right: Expression)
    case unaryOperation(operator: UnaryOperator, operand: Expression)
    
    case chunkExpression(type: ChunkType, first: Expression, last: Expression?, string: Expression) // e.g. word 1 of Entry
    case elementRangeAccess(target: Expression, start: Expression, end: Expression)
    case lastStringChunk(type: ChunkType, obj: Expression)
    case stringChunkCount(type: ChunkType, obj: Expression)
    
    case spriteIntersects(first: Expression, second: Expression)
    case spriteWithin(first: Expression, second: Expression)
    case member(type: String, id: Expression, castId: Expression?)
    case menuProp(menuId: Expression, prop: String)
    case menuItemProp(menuId: Expression, itemId: Expression, prop: String)
    case soundProp(soundId: Expression, prop: String)
    case spriteProp(spriteId: Expression, prop: String)
    case newObj(type: String, args: Expression)
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
    case contains = "contains"
    case starts = "starts"
}

public enum UnaryOperator: String, Equatable {
    case negate = "-"
    case not = "not"
}

public enum PutType: Equatable {
    case into
    case after
    case before
    case display
}
