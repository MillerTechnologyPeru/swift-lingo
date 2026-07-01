public enum LingoBytecodeError: Error, Equatable {
    case unknownOpcode(UInt8)
    case unknownLiteralType(UInt32)
    case invalidOffset(Int)
}
