import BinaryParsing
import LingoBytecode

/// Errors `LingoAssembler.build()` can throw.
public enum LingoAssemblerError: Error, Equatable {
    /// A `jump`/`jumpIfZero`/`endRepeat` targeted a label that was never
    /// `mark()`-ed.
    case unresolvedLabel
    /// A resolved jump's byte distance doesn't fit the format's 16-bit
    /// unsigned offset (or a backward jump's target wasn't actually behind
    /// it, or vice versa for a forward jump).
    case invalidJumpOffset
}

/// A small bytecode-assembler DSL for hand-authoring `HandlerDef`s readably,
/// instead of as commented `[UInt8]` arrays. Exists because this repo has no
/// `.ls`-source-to-bytecode compiler and no movie-file parser to pull real
/// bytecode out of a `.dir`/`.dcr` — the only way to feed `LingoVM` anything
/// is hand-authored bytecode, and this makes that authoring readable.
///
/// Covers the opcodes needed for realistic straight-line, control-flow,
/// call, and property scripts — not literally every opcode `LingoVMExecutor`
/// handles (chunk expressions, V4 legacy properties, sprite geometry,
/// `newObj` are out of scope). `HandlerDef.bytecodeArray` is a plain
/// `[Bytecode]`, so anything this assembler doesn't cover can still be
/// hand-appended the same way existing tests already do.
public final class LingoAssembler {
    /// An opaque jump target, created with `makeLabel()` and fixed to a
    /// specific instruction position with `mark(_:)`.
    public final class Label {
        fileprivate var position: Int?
        public init() {}
    }

    private struct PendingJump {
        var operandByteOffset: Int
        var label: Label
        var backward: Bool
    }

    private var bytes: [UInt8] = []
    private var names: [String]
    private var literals: [LiteralValue]
    private var argumentNameIds: [UInt16] = []
    private var localNameIds: [UInt16] = []
    private var argumentSlots: [String: Int] = [:]
    private var localSlots: [String: Int] = [:]
    private var pendingJumps: [PendingJump] = []
    private let multiplier: UInt32

    /// - Parameters:
    ///   - arguments: This handler's parameter names, in order — reads/writes
    ///     via `get`/`set` classify a name found here as `GetParam`/`SetParam`.
    ///   - locals: This handler's local variable names — classified as
    ///     `GetLocal`/`SetLocal`. A name in neither list is treated as a
    ///     global (`GetGlobal`/`SetGlobal`).
    ///   - names: The shared movie-level name table to intern into, starting
    ///     from whatever's already there (matching `LingoBytecode.decompile`'s
    ///     own shared-table convention).
    ///   - literals: The chunk-level literal pool to intern into, starting
    ///     from whatever's already there — needed to keep multiple handlers'
    ///     literal-pool indices consistent when they share one `ScriptChunk`
    ///     (chain each handler's `build()` output into the next's `literals:`,
    ///     the same way `names:` chains).
    ///   - version: Selects the variable-id scaling factor, matching
    ///     `LingoBytecode.decompile`/`LingoVM.call`.
    ///   - capitalX: Whether to use the newer `LctX` direct-addressing scale
    ///     (multiplier 1) instead of the version-dependent one.
    public init(
        arguments: [String] = [], locals: [String] = [], names: [String] = [],
        literals: [LiteralValue] = [], version: UInt16 = 500, capitalX: Bool = false
    ) {
        self.names = names
        self.literals = literals
        self.multiplier = capitalX ? 1 : (version >= 500 ? 8 : 6)
        for argument in arguments {
            argumentSlots[argument] = argumentNameIds.count
            argumentNameIds.append(internName(argument))
        }
        for local in locals {
            localSlots[local] = localNameIds.count
            localNameIds.append(internName(local))
        }
    }

    // MARK: - Name/literal interning

    @discardableResult
    private func internName(_ name: String) -> UInt16 {
        if let index = names.firstIndex(of: name) {
            return UInt16(index)
        }
        names.append(name)
        return UInt16(names.count - 1)
    }

    private func internLiteral(_ literal: LiteralValue) -> Int {
        if let index = literals.firstIndex(of: literal) {
            return index
        }
        literals.append(literal)
        return literals.count - 1
    }

    // MARK: - Raw emission

    /// Appends a single-byte, no-operand opcode (raw value < 0x40).
    @discardableResult
    private func emit(_ opcode: OpCode) -> Self {
        bytes.append(opcode.rawValue)
        return self
    }

    /// Appends a multi-byte opcode with an operand, picking the
    /// smallest-fitting tier per `Bytecode.swift`'s decode rule: raw byte
    /// `0x40...0x7F` + 1 operand byte, or `0x80 + (opcode - 0x40)` + 2
    /// operand bytes big-endian. `signed` selects `Int8`/`Int16` instead of
    /// `UInt8`/`UInt16`, matching `pushInt8`/`pushInt16`'s decode.
    @discardableResult
    private func emit(_ opcode: OpCode, _ operand: Int64, signed: Bool = false) -> Self {
        if signed {
            if let small = Int8(exactly: operand) {
                bytes.append(opcode.rawValue)
                bytes.append(UInt8(bitPattern: small))
            } else {
                let wide = Int16(clamping: operand)
                bytes.append(0x80 + (opcode.rawValue - 0x40))
                bytes.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: wide) >> 8))
                bytes.append(UInt8(truncatingIfNeeded: UInt16(bitPattern: wide)))
            }
        } else {
            if operand >= 0, let small = UInt8(exactly: operand) {
                bytes.append(opcode.rawValue)
                bytes.append(small)
            } else {
                let wide = UInt16(clamping: max(0, operand))
                bytes.append(0x80 + (opcode.rawValue - 0x40))
                bytes.append(UInt8(truncatingIfNeeded: wide >> 8))
                bytes.append(UInt8(truncatingIfNeeded: wide))
            }
        }
        return self
    }

    /// Appends a jump-family opcode with a placeholder operand, always in
    /// the 2-byte tier — every instruction's byte position is then known
    /// immediately, with no fixed-point sizing pass needed to resolve
    /// labels afterward. Records the patch to apply once every label's
    /// position is known, in `build()`.
    private func emitJump(_ opcode: OpCode, to label: Label, backward: Bool) {
        bytes.append(0x80 + (opcode.rawValue - 0x40))
        let operandOffset = bytes.count
        bytes.append(0)
        bytes.append(0)
        pendingJumps.append(PendingJump(operandByteOffset: operandOffset, label: label, backward: backward))
    }

    // MARK: - Literals / stack

    /// Smallest-fitting tier: `PushZero` for `0`, `PushInt8` (1- or 2-byte
    /// operand tier, covering the full `Int16` range) otherwise. Values
    /// outside `Int16` route through the literal pool instead of
    /// `PushInt32` — `PushInt32`'s operand decodes as *unsigned* per
    /// `Bytecode.swift`'s current (documented, pre-existing) two-tier
    /// decoder, so it can't actually hold a full signed 32-bit value;
    /// the literal pool has no such limitation.
    @discardableResult
    public func pushInt(_ value: Int) -> Self {
        if value == 0 {
            return emit(.pushZero)
        }
        if Int8(exactly: value) != nil || Int16(exactly: value) != nil {
            return emit(.pushInt8, Int64(value), signed: true)
        }
        return pushLiteral(.int(Int32(value)))
    }

    @discardableResult
    public func pushFloat(_ value: Double) -> Self {
        pushLiteral(.double(value))
    }

    @discardableResult
    public func pushString(_ value: String) -> Self {
        pushLiteral(.string(value))
    }

    @discardableResult
    private func pushLiteral(_ literal: LiteralValue) -> Self {
        let index = internLiteral(literal)
        return emit(.pushCons, Int64(index) * Int64(multiplier))
    }

    @discardableResult
    public func pushSymbol(_ value: String) -> Self {
        emit(.pushSymb, Int64(internName(value)))
    }

    @discardableResult
    public func pop(_ count: Int = 1) -> Self {
        emit(.pop, Int64(count))
    }

    @discardableResult
    public func peek(_ depth: Int = 0) -> Self {
        emit(.peek, Int64(depth))
    }

    // MARK: - Variables

    /// Reads `name`, classified as a param/local/global by whether it
    /// appears in this assembler's `arguments`/`locals` lists.
    @discardableResult
    public func get(_ name: String) -> Self {
        if let slot = argumentSlots[name] {
            return emit(.getParam, Int64(slot) * Int64(multiplier))
        }
        if let slot = localSlots[name] {
            return emit(.getLocal, Int64(slot) * Int64(multiplier))
        }
        return emit(.getGlobal, Int64(internName(name)))
    }

    /// Writes the top of the stack into `name`, classified the same way as
    /// `get`.
    @discardableResult
    public func set(_ name: String) -> Self {
        if let slot = argumentSlots[name] {
            return emit(.setParam, Int64(slot) * Int64(multiplier))
        }
        if let slot = localSlots[name] {
            return emit(.setLocal, Int64(slot) * Int64(multiplier))
        }
        return emit(.setGlobal, Int64(internName(name)))
    }

    // MARK: - String joins

    /// Lingo `&`.
    @discardableResult public func joinStr() -> Self { emit(.joinStr) }
    /// Lingo `&&` (single space between).
    @discardableResult public func joinPadStr() -> Self { emit(.joinPadStr) }

    // MARK: - Arithmetic / comparison / logic

    @discardableResult public func add() -> Self { emit(.add) }
    @discardableResult public func sub() -> Self { emit(.sub) }
    @discardableResult public func mul() -> Self { emit(.mul) }
    @discardableResult public func div() -> Self { emit(.div) }
    @discardableResult public func mod() -> Self { emit(.mod) }
    @discardableResult public func inv() -> Self { emit(.inv) }
    @discardableResult public func not() -> Self { emit(.not) }
    @discardableResult public func and() -> Self { emit(.and) }
    @discardableResult public func or() -> Self { emit(.or) }
    @discardableResult public func lt() -> Self { emit(.lt) }
    @discardableResult public func ltEq() -> Self { emit(.ltEq) }
    @discardableResult public func gt() -> Self { emit(.gt) }
    @discardableResult public func gtEq() -> Self { emit(.gtEq) }
    @discardableResult public func eq() -> Self { emit(.eq) }
    @discardableResult public func ntEq() -> Self { emit(.ntEq) }

    // MARK: - Calls / properties

    @discardableResult
    public func pushArgList(_ count: Int) -> Self {
        emit(.pushArgList, Int64(count))
    }

    @discardableResult
    public func pushArgListNoRet(_ count: Int) -> Self {
        emit(.pushArgListNoRet, Int64(count))
    }

    /// Calls another handler in the same `ScriptChunk`, addressed by its
    /// ordinal position in `ScriptChunk.handlers` — the caller assembling
    /// the chunk owns that ordering, the same division of responsibility
    /// `LingoVMExecutor`'s own `LocalCall` handling already has.
    @discardableResult
    public func localCall(_ handlerIndex: Int) -> Self {
        emit(.localCall, Int64(handlerIndex))
    }

    @discardableResult
    public func extCall(_ name: String) -> Self {
        emit(.extCall, Int64(internName(name)))
    }

    @discardableResult
    public func objCall(_ name: String) -> Self {
        emit(.objCall, Int64(internName(name)))
    }

    @discardableResult
    public func getObjProp(_ name: String) -> Self {
        emit(.getObjProp, Int64(internName(name)))
    }

    @discardableResult
    public func setObjProp(_ name: String) -> Self {
        emit(.setObjProp, Int64(internName(name)))
    }

    @discardableResult
    public func ret() -> Self {
        emit(.ret)
    }

    // MARK: - Control flow

    public func makeLabel() -> Label { Label() }

    /// Fixes `label` to the position of the *next* instruction appended
    /// after this call.
    @discardableResult
    public func mark(_ label: Label) -> Self {
        label.position = bytes.count
        return self
    }

    @discardableResult
    public func jump(to label: Label) -> Self {
        emitJump(.jmp, to: label, backward: false)
        return self
    }

    @discardableResult
    public func jumpIfZero(to label: Label) -> Self {
        emitJump(.jmpIfZ, to: label, backward: false)
        return self
    }

    /// A `repeat` loop's back-edge: jumps to `label` (already `mark()`-ed,
    /// at the loop's condition check) from the current position.
    @discardableResult
    public func endRepeat(to label: Label) -> Self {
        emitJump(.endRepeat, to: label, backward: true)
        return self
    }

    // MARK: - Structured control flow

    /// `if <condition> then <then> end if` — `condition` must leave exactly
    /// one value on the stack (truthy/falsy), consumed by the generated
    /// `JmpIfZ`. Built entirely from the primitives above; equivalent to
    /// calling them directly, just without naming the label.
    @discardableResult
    public func ifThen(condition: () -> Void, then: () -> Void) -> Self {
        condition()
        let endLabel = makeLabel()
        jumpIfZero(to: endLabel)
        then()
        mark(endLabel)
        return self
    }

    /// `if <condition> then <then> else <elseBody> end if`.
    @discardableResult
    public func ifThenElse(condition: () -> Void, then: () -> Void, else elseBody: () -> Void) -> Self {
        condition()
        let elseLabel = makeLabel()
        let endLabel = makeLabel()
        jumpIfZero(to: elseLabel)
        then()
        jump(to: endLabel)
        mark(elseLabel)
        elseBody()
        mark(endLabel)
        return self
    }

    /// `repeat while <condition> <body> end repeat` — the same shape proven
    /// by `LingoVMHarnessTests`' hand-assembled loop examples, just built
    /// for you instead of by hand.
    @discardableResult
    public func repeatWhile(condition: () -> Void, body: () -> Void) -> Self {
        let conditionLabel = makeLabel()
        let endLabel = makeLabel()
        mark(conditionLabel)
        condition()
        jumpIfZero(to: endLabel)
        body()
        endRepeat(to: conditionLabel)
        mark(endLabel)
        return self
    }

    /// `repeat with <variable> = <start> to <end> <body> end repeat`
    /// (inclusive of `end`). `variable` should be one of this assembler's
    /// declared `locals`/`arguments` to address it efficiently — otherwise
    /// it's treated as a global, the same as any other `get`/`set` call.
    @discardableResult
    public func repeatWithCounter(_ variable: String, from start: Int, to end: Int, body: () -> Void) -> Self {
        pushInt(start).set(variable)
        return repeatWhile(
            condition: { self.get(variable).pushInt(end).ltEq() },
            body: {
                body()
                self.get(variable).pushInt(1).add().set(variable)
            })
    }

    // MARK: - Build

    /// Resolves every pending jump, parses the finished byte stream into
    /// `Bytecode`s the same way every existing bytecode-consuming test
    /// does, and returns a `HandlerDef` plus the shared `names`/`literals`
    /// arrays a caller assembles into a `ScriptChunk`.
    public func build() throws -> (handler: HandlerDef, names: [String], literals: [LiteralValue]) {
        for jump in pendingJumps {
            guard let targetPosition = jump.label.position else {
                throw LingoAssemblerError.unresolvedLabel
            }
            // `Bytecode`'s jump opcodes measure their offset from their own
            // opcode byte, one byte before the 2-byte operand this patches.
            let opcodePosition = jump.operandByteOffset - 1
            let offset = jump.backward ? opcodePosition - targetPosition : targetPosition - opcodePosition
            guard let value = UInt16(exactly: offset) else {
                throw LingoAssemblerError.invalidJumpOffset
            }
            bytes[jump.operandByteOffset] = UInt8(truncatingIfNeeded: value >> 8)
            bytes[jump.operandByteOffset + 1] = UInt8(truncatingIfNeeded: value)
        }

        let bytecodeArray = try bytes.withParserSpan { span -> [Bytecode] in
            var array: [Bytecode] = []
            while !span.isEmpty {
                array.append(try Bytecode(parsing: &span))
            }
            return array
        }

        let handler = HandlerDef(
            nameId: 0, bytecodeArray: bytecodeArray, argumentNameIds: argumentNameIds,
            localNameIds: localNameIds, globalNameIds: [])
        return (handler, names, literals)
    }
}
