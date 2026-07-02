/// Supporting enums for the bytecode decompiler. Internal to the decompiler —
/// never exposed as part of `LingoBytecode`'s public surface, which only
/// emits `LingoAST.Statement`/`Expression`.

enum DatumType: Equatable {
    case void
    case symbol
    case varRef
    case string
    case int
    case float
    case list
    case argList
    case argListNoRet
    case propList
}

enum ChunkExprType: UInt8, Equatable {
    case char = 0x01
    case word = 0x02
    case item = 0x03
    case line = 0x04

    var name: String {
        switch self {
        case .char: return "char"
        case .word: return "word"
        case .item: return "item"
        case .line: return "line"
        }
    }
}

enum PutType: UInt8, Equatable {
    case into = 0x01
    case after = 0x02
    case before = 0x03

    var name: String {
        switch self {
        case .into: return "into"
        case .after: return "after"
        case .before: return "before"
        }
    }
}

enum CaseExpect: Equatable {
    case end
    case or
    case next
    case otherwise
}
