import Testing
import LingoRuntime

@testable import LingoVM

@Test func objPropGetSetDispatchesToAnArbitraryObject() throws {
    let receiver = TestReceiver()
    LingoEnvironment.shared.setGlobal("vmTestObjPropTarget", .object(receiver))

    let executor = try makeExecutor(
        bytes: [
            0x49, 0x00,  // GetGlobal vmTestObjPropTarget
            0x41, 0x07,  // PushInt8 7
            0x62, 0x01,  // SetObjProp y
            0x49, 0x00,  // GetGlobal vmTestObjPropTarget
            0x61, 0x01,  // GetObjProp y
            0x01  // Ret
        ],
        names: ["vmTestObjPropTarget", "y"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(7)))
}

@Test func getObjPropOnNonObjectReturnsVoid() throws {
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x01,  // PushInt8 1 (not an object)
            0x61, 0x00,  // GetObjProp x
            0x01  // Ret
        ],
        names: ["x"])
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
}

@Test func movieGetSetDispatchesToHostMovie() throws {
    let host = TestHost()
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x02,  // PushInt8 2
            0x60, 0x00,  // SetMovieProp floatPrecision
            0x5f, 0x00,  // GetMovieProp floatPrecision
            0x01  // Ret
        ],
        names: ["floatPrecision"], host: host)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(2)))
}

@Test func movieGetWithNoHostReturnsVoid() throws {
    let executor = try makeExecutor(bytes: [0x5f, 0x00], names: ["floatPrecision"], host: nil)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
}

@Test func v4GetSetResolvesSpritePropertyThroughHost() throws {
    let host = TestHost()
    let sprite = TestReceiver()
    host.sprites[3] = sprite

    // "set the locH of sprite 3 to 99" then read it back.
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x03,  // PushInt8 3   (spriteId, for Set's inner readVar-style pop)
            0x41, 0x63,  // PushInt8 99  (value)
            0x41, 0x0d,  // PushInt8 13  (propId: locH)
            0x5d, 0x06,  // Set propertyType=6 (sprite)
            0x41, 0x03,  // PushInt8 3   (spriteId again, for Get)
            0x41, 0x0d,  // PushInt8 13  (propId again)
            0x5c, 0x06,  // Get propertyType=6 (sprite)
            0x01  // Ret
        ],
        host: host)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(99)))
    #expect(LingoValue.equalsBool(lhs: sprite.properties["locH"] ?? .void, rhs: .integer(99)))
}

@Test func v4GetUnresolvedSpriteReturnsVoid() throws {
    let host = TestHost()
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x63,  // PushInt8 99 (unregistered sprite channel)
            0x41, 0x0d,  // PushInt8 13 (locH)
            0x5c, 0x06,  // Get propertyType=6 (sprite)
            0x01  // Ret
        ],
        host: host)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
}

@Test func v4GetResolvesMemberPropertyThroughHost() throws {
    let host = TestHost()
    let member = TestReceiver()
    host.members[1] = member
    member.properties["name"] = .string("myMember")

    // makeExecutor always runs at version 500+, so a member property pops a
    // castLib operand too (member id, then castLib, then the property id).
    let executor = try makeExecutor(
        bytes: [
            0x41, 0x01,  // PushInt8 1  (memberId)
            0x41, 0x00,  // PushInt8 0  (castLib)
            0x41, 0x01,  // PushInt8 1  (propId: name)
            0x5c, 0x09,  // Get propertyType=9 (member)
            0x01  // Ret
        ],
        host: host)
    let result = try executor.run()

    #expect(LingoValue.equalsBool(lhs: result, rhs: .string("myMember")))
}
