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

enum CaseExpect: Equatable {
    case end
    case or
    case next
    case otherwise
}

/// Tags applied to specific bytecode indices during loop identification, so
/// the main decode pass can skip a loop's internal setup/teardown
/// instructions and recognize jumps back to them as `exit repeat`/`next
/// repeat` rather than a generic, unrecognized jump.
enum BytecodeTag: Equatable {
    case none
    case skip
    case repeatWhile
    case repeatWithIn
    case repeatWithTo
    case repeatWithDownTo
    case nextRepeatTarget
    case endCase
}
