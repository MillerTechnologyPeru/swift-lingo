import LingoAST

/// The bytecode decompiler's internal intermediate tree, built up during
/// stack-machine simulation before being converted into
/// `LingoAST.Statement`/`Expression` — the only type this module exposes
/// publicly. It never escapes `LingoBytecode`.
///
/// `put`'s statement reuses `LingoAST.PutType` directly (`.into`/`.after`/
/// `.before`) rather than declaring an equivalent decompiler-local copy,
/// since the shapes are identical and this tree's only consumer is the
/// conversion into `LingoAST` itself.
///
/// Most node kinds are built once and never mutated afterward, so `AstNode`
/// is a plain `indirect enum` (a value type). The two variants whose fields
/// do need to change after construction — `ifStatement` (once an else branch
/// is found) and `caseStatement` (as case labels are discovered) — hold a
/// small class of their own instead, since Swift classes already provide
/// shared, mutable reference semantics via ARC. The same reasoning makes
/// `BlockNode`/`CaseLabelNode`/`OtherwiseNode` plain classes: the decompiler
/// keeps building them up (e.g. `addChild`) after they're already referenced
/// elsewhere in the tree.

/// Decompiler-local value representation, distinct from `LingoAST`'s own
/// literal/value model — this one only needs to describe what the bytecode's
/// literal pool and stack machine can produce.
struct Datum {
    var datumType: DatumType
    var intValue: Int32
    var floatValue: Double
    var stringValue: String
    var listValue: [AstNode]

    static func void() -> Datum {
        Datum(datumType: .void, intValue: 0, floatValue: 0, stringValue: "", listValue: [])
    }

    static func int(_ value: Int32) -> Datum {
        Datum(datumType: .int, intValue: value, floatValue: 0, stringValue: "", listValue: [])
    }

    static func float(_ value: Double) -> Datum {
        Datum(datumType: .float, intValue: 0, floatValue: value, stringValue: "", listValue: [])
    }

    static func string(_ value: String) -> Datum {
        Datum(datumType: .string, intValue: 0, floatValue: 0, stringValue: value, listValue: [])
    }

    static func symbol(_ value: String) -> Datum {
        Datum(datumType: .symbol, intValue: 0, floatValue: 0, stringValue: value, listValue: [])
    }

    static func varRef(_ value: String) -> Datum {
        Datum(datumType: .varRef, intValue: 0, floatValue: 0, stringValue: value, listValue: [])
    }

    static func list(_ items: [AstNode]) -> Datum {
        Datum(datumType: .list, intValue: 0, floatValue: 0, stringValue: "", listValue: items)
    }

    static func argList(_ items: [AstNode]) -> Datum {
        Datum(datumType: .argList, intValue: 0, floatValue: 0, stringValue: "", listValue: items)
    }

    static func argListNoRet(_ items: [AstNode]) -> Datum {
        Datum(datumType: .argListNoRet, intValue: 0, floatValue: 0, stringValue: "", listValue: items)
    }

    static func propList(_ items: [AstNode]) -> Datum {
        Datum(datumType: .propList, intValue: 0, floatValue: 0, stringValue: "", listValue: items)
    }

    func toInt() -> Int32 {
        switch datumType {
        case .int: return intValue
        case .float: return Int32(floatValue)
        default: return 0
        }
    }
}

/// A child statement within a block, pairing the AST node with the bytecode
/// indices it was decompiled from.
struct BlockChild {
    var node: AstNode
    var bytecodeIndices: [Int]
}

/// Container for a sequence of statements. A class because the decompiler
/// builds it up incrementally (`addChild`) while other already-constructed
/// nodes (e.g. an enclosing `ifStatement`) hold a reference to it.
final class BlockNode {
    var children: [BlockChild] = []
    var endPos: UInt32 = .max
    var currentCaseLabel: CaseLabelNode?

    init() {}

    func addChild(_ node: AstNode, bytecodeIndices: [Int]) {
        children.append(BlockChild(node: node, bytecodeIndices: bytecodeIndices))
    }
}

/// Mutable payload for `AstNode.ifStatement`. `hasElse` starts `false` and is
/// flipped once the decompiler detects a jump past an else branch.
final class IfNode {
    var condition: AstNode
    var block1: BlockNode
    var block2: BlockNode
    var hasElse: Bool

    init(condition: AstNode, block1: BlockNode, block2: BlockNode, hasElse: Bool = false) {
        self.condition = condition
        self.block1 = block1
        self.block2 = block2
        self.hasElse = hasElse
    }
}

/// Mutable payload for `AstNode.caseStatement`. `firstLabel`/`otherwise` are
/// filled in as case labels are discovered; `endPos`/`potentialOtherwisePos`
/// default to -1, meaning "not yet known".
final class CaseNode {
    var value: AstNode
    var firstLabel: CaseLabelNode?
    var otherwise: OtherwiseNode?
    var endPos: Int32
    var potentialOtherwisePos: Int32

    init(
        value: AstNode,
        firstLabel: CaseLabelNode? = nil,
        otherwise: OtherwiseNode? = nil,
        endPos: Int32 = -1,
        potentialOtherwisePos: Int32 = -1
    ) {
        self.value = value
        self.firstLabel = firstLabel
        self.otherwise = otherwise
        self.endPos = endPos
        self.potentialOtherwisePos = potentialOtherwisePos
    }
}

/// One comma-chained label (and its block) within a `case` statement,
/// linked to the next label via `nextLabel`.
final class CaseLabelNode {
    var value: AstNode
    var expect: CaseExpect
    var nextOr: CaseLabelNode?
    var nextLabel: CaseLabelNode?
    var block: BlockNode

    init(value: AstNode, expect: CaseExpect) {
        self.value = value
        self.expect = expect
        self.nextOr = nil
        self.nextLabel = nil
        self.block = BlockNode()
    }
}

/// The `otherwise:` branch of a `case` statement.
final class OtherwiseNode {
    var block: BlockNode

    init() {
        self.block = BlockNode()
    }
}

/// The decompiler's intermediate tree node. An `indirect enum` (a value
/// type) is sufficient for the majority of cases, which are built once and
/// never mutated afterward. Only `ifStatement`/`caseStatement` need
/// post-construction mutation, so those route through the small classes
/// above instead.
indirect enum AstNode {
    case error
    case comment(String)
    case literal(Datum)
    case block(BlockNode)
    case variable(String)
    case assignment(variable: AstNode, value: AstNode, forceVerbose: Bool)
    case binaryOp(opcode: OpCode, left: AstNode, right: AstNode)
    case inverseOp(AstNode)
    case notOp(AstNode)
    case chunkExpr(chunkType: ChunkExprType, first: AstNode, last: AstNode, string: AstNode)
    case chunkHilite(AstNode)
    case chunkDelete(AstNode)
    case spriteIntersects(first: AstNode, second: AstNode)
    case spriteWithin(first: AstNode, second: AstNode)
    case member(memberType: String, memberID: AstNode, castID: AstNode?)
    case the(String)
    case theProp(obj: AstNode, prop: String)
    case objProp(obj: AstNode, prop: String)
    case objBracket(obj: AstNode, prop: AstNode)
    case objPropIndex(obj: AstNode, prop: String, index: AstNode, index2: AstNode?)
    case lastStringChunk(chunkType: ChunkExprType, obj: AstNode)
    case stringChunkCount(chunkType: ChunkExprType, obj: AstNode)
    case menuProp(menuID: AstNode, prop: UInt32)
    case menuItemProp(menuID: AstNode, itemID: AstNode, prop: UInt32)
    case soundProp(soundID: AstNode, prop: UInt32)
    case spriteProp(spriteID: AstNode, prop: UInt32)
    case call(name: String, args: AstNode)
    case objCall(name: String, args: AstNode)
    case objCallV4(obj: AstNode, args: AstNode)
    case exit
    case exitRepeat
    case nextRepeat
    case put(putType: PutType, variable: AstNode, value: AstNode)
    case ifStatement(IfNode)
    case repeatWhile(condition: AstNode, block: BlockNode, startIndex: UInt32)
    case repeatWithIn(varName: String, list: AstNode, block: BlockNode, startIndex: UInt32)
    case repeatWithTo(
        varName: String, start: AstNode, end: AstNode, up: Bool, block: BlockNode, startIndex: UInt32)
    case tell(window: AstNode, block: BlockNode)
    case caseStatement(CaseNode)
    case newObj(objType: String, args: AstNode)
    case when(event: Int32, script: String)
    case soundCmd(cmd: String, args: AstNode)
    case playCmd(args: AstNode)

    /// True for node kinds that produce a value when evaluated. Mirrors
    /// `AstNode::is_expression` — `call`/`objCall`/`objCallV4` are
    /// expressions unless their argument list is a no-return arg list (i.e.
    /// the call was made as a statement).
    var isExpression: Bool {
        switch self {
        case .literal, .variable, .binaryOp, .inverseOp, .notOp, .chunkExpr, .member, .the,
            .theProp, .objProp, .objBracket, .objPropIndex, .lastStringChunk, .stringChunkCount,
            .menuProp, .menuItemProp, .soundProp, .spriteProp, .spriteIntersects, .spriteWithin,
            .newObj:
            return true
        case .call(_, let args), .objCall(_, let args), .objCallV4(_, let args):
            if case .literal(let datum) = args {
                return datum.datumType != .argListNoRet
            }
            return true
        default:
            return false
        }
    }

    /// True for node kinds that stand alone as a full statement. Mirrors
    /// `AstNode::is_statement`, the logical complement of `isExpression` for
    /// the `call`/`objCall`/`objCallV4` variants.
    var isStatement: Bool {
        switch self {
        case .assignment, .exit, .exitRepeat, .nextRepeat, .put, .ifStatement, .repeatWhile,
            .repeatWithIn, .repeatWithTo, .tell, .caseStatement, .chunkHilite, .chunkDelete,
            .when, .soundCmd, .playCmd:
            return true
        case .call(_, let args), .objCall(_, let args), .objCallV4(_, let args):
            if case .literal(let datum) = args {
                return datum.datumType == .argListNoRet
            }
            return false
        default:
            return false
        }
    }

    /// The literal `Datum` this node holds, if it's a `literal` node.
    /// Mirrors `AstNode::get_value`.
    var value: Datum? {
        if case .literal(let datum) = self {
            return datum
        }
        return nil
    }
}
