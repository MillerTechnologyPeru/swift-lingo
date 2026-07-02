import LingoRuntime

/// A reusable `LingoVMHost` for exercising `LingoVM` without a real Director
/// runtime — resolves sprites/members/menus/sounds/windows by integer id
/// from plain dictionaries, and exposes the two behavior hooks
/// (`makeObject`, sprite-geometry collision) as settable closures so a
/// scenario can plug in real logic without subclassing.
open class HarnessHost: LingoVMHost {
    public let movie: LingoObject
    public var sprites: [Int: LingoObject] = [:]
    public var members: [Int: LingoObject] = [:]
    public var menus: [Int: LingoObject] = [:]
    public var sounds: [Int: LingoObject] = [:]
    public var windows: [Int: LingoObject] = [:]

    public var makeObjectHandler: ((String, [LingoValue]) -> LingoObject?)?
    public var spriteIntersectsHandler: ((LingoObject, LingoObject) -> Bool)?
    public var spriteWithinHandler: ((LingoObject, LingoObject) -> Bool)?
    public var hiliteHandler: ((LingoObject, String, LingoValue, LingoValue) -> Void)?

    public init(environment: LingoEnvironment, movie: LingoObject? = nil) {
        self.movie = movie ?? HarnessObject(environment: environment)
    }

    public func sprite(_ channel: LingoValue) -> LingoObject? {
        guard let index = channel.asInteger() else { return nil }
        return sprites[index]
    }

    public func member(_ id: LingoValue, castLib: LingoValue?) -> LingoObject? {
        guard let index = id.asInteger() else { return nil }
        return members[index]
    }

    public func menu(_ id: LingoValue) -> LingoObject? {
        guard let index = id.asInteger() else { return nil }
        return menus[index]
    }

    public func sound(_ id: LingoValue) -> LingoObject? {
        guard let index = id.asInteger() else { return nil }
        return sounds[index]
    }

    public func window(_ id: LingoValue) -> LingoObject? {
        guard let index = id.asInteger() else { return nil }
        return windows[index]
    }

    public func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject? {
        makeObjectHandler?(scriptName, args)
    }

    public func spriteIntersects(_ a: LingoObject, _ b: LingoObject) -> Bool {
        spriteIntersectsHandler?(a, b) ?? false
    }

    public func spriteWithin(_ a: LingoObject, _ b: LingoObject) -> Bool {
        spriteWithinHandler?(a, b) ?? false
    }

    public func hilite(_ member: LingoObject, type: String, first: LingoValue, last: LingoValue) {
        hiliteHandler?(member, type, first, last)
    }
}
