import Testing
import LingoRuntime

@testable import LingoVM

@Test func integratedProgramCombiningCallsLoopsAndProperties() throws {
    // handler double(n)
    //   return n * 2
    // end
    //
    // handler main(n)
    //   local i = 0
    //   local total = double(n)
    //   repeat while i < 3
    //     total = total + 1
    //     i = i + 1
    //   end repeat
    //   me.result = total
    //   return me.result
    // end
    //
    // main(5): double(5)=10, then +1 three times -> 13.
    let doubleHandler = try makeHandler(bytes: [
        0x4b, 0x00,  // GetParam 0 (n)
        0x41, 0x02,  // PushInt8 2
        0x04,  // Mul
        0x01  // Ret
    ])

    let bytes: [UInt8] = [
        0x03,  // 0: PushZero
        0x52, 0x00,  // 1: SetLocal 0        (i = 0)
        0x4b, 0x00,  // 3: GetParam 0        (n)
        0x43, 0x01,  // 5: PushArgList 1
        0x56, 0x00,  // 7: LocalCall double
        0x52, 0x08,  // 9: SetLocal 1        (total = double(n))
        0x4c, 0x00,  // 11: GetLocal 0       (i)               <- loop condition
        0x41, 0x03,  // 13: PushInt8 3
        0x0c,  // 15: Lt                (i < 3)
        0x55, 0x12,  // 16: JmpIfZ -> 16+18=34
        0x4c, 0x08,  // 18: GetLocal 1       (total)
        0x41, 0x01,  // 20: PushInt8 1
        0x05,  // 22: Add
        0x52, 0x08,  // 23: SetLocal 1       (total += 1)
        0x4c, 0x00,  // 25: GetLocal 0       (i)
        0x41, 0x01,  // 27: PushInt8 1
        0x05,  // 29: Add
        0x52, 0x00,  // 30: SetLocal 0       (i += 1)
        0x54, 0x15,  // 32: EndRepeat -> 32-21=11
        0x4c, 0x08,  // 34: GetLocal 1       (total)           <- after the loop
        0x50, 0x00,  // 36: SetProp result   (me.result = total)
        0x4a, 0x00,  // 38: GetProp result   (me.result)
        0x01  // 40: Ret
    ]

    let receiver = TestReceiver()
    let executor = try makeExecutor(
        bytes: bytes, names: ["result"], args: [.integer(5)], localCount: 2, receiver: receiver,
        handlers: [doubleHandler])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(13)))
    #expect(LingoValue.equalsBool(lhs: receiver.properties["result"] ?? .void, rhs: .integer(13)))
}

@Test func integratedProgramWithHostBackedSpriteAndMovieAccess() throws {
    // handler main()
    //   set the floatPrecision to 4
    //   set the locH of sprite 1 to 100
    //   return (the floatPrecision) + (the locH of sprite 1)
    // end
    let host = TestHost()
    let sprite = TestReceiver()
    host.sprites[1] = sprite

    let bytes: [UInt8] = [
        0x41, 0x04,  // PushInt8 4
        0x60, 0x00,  // SetMovieProp floatPrecision
        0x41, 0x01,  // PushInt8 1   (spriteId)
        0x41, 0x64,  // PushInt8 100 (value)
        0x41, 0x0d,  // PushInt8 13  (propId: locH)
        0x5d, 0x06,  // Set propertyType=6 (sprite)
        0x5f, 0x00,  // GetMovieProp floatPrecision
        0x41, 0x01,  // PushInt8 1   (spriteId)
        0x41, 0x0d,  // PushInt8 13  (propId: locH)
        0x5c, 0x06,  // Get propertyType=6 (sprite)
        0x05,  // Add
        0x01  // Ret
    ]

    let executor = try makeExecutor(bytes: bytes, names: ["floatPrecision"], host: host)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(104)))
    #expect(LingoValue.equalsBool(lhs: sprite.properties["locH"] ?? .void, rhs: .integer(100)))
}
