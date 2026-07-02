import LingoBytecode

/// Errors the VM raises for genuinely exceptional conditions. Most Lingo
/// runtime "failures" (a missing property, dividing by zero, an unresolved
/// object) are not exceptional at all — Lingo itself treats them as `VOID`
/// or a no-op, and `LingoValue`'s own operators already encode that. This
/// type is reserved for conditions a well-formed compiled handler should
/// never hit.
public enum LingoVMError: Error, Equatable {
    case unknownOpcode(OpCode)
    case invalidJumpTarget(Int)
    case stackUnderflow
    case recursionLimitExceeded
    case unknownLocalHandler(Int)
}
