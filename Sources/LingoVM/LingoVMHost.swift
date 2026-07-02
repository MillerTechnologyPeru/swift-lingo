import LingoRuntime

/// The VM's only escape hatch for anything host/Director-specific. Property
/// and method dispatch on objects the VM already has a reference to goes
/// through `LingoObject`/`LingoEnvironment` directly — this protocol only
/// covers the things neither of those can resolve on their own: *which*
/// object "the movie", "sprite N", "member X", or "window Y" refers to, how
/// to instantiate a new script object by name, and sprite-geometry
/// collision queries (kept entirely out of the VM).
///
/// Every requirement except `movie` has a default that mirrors Lingo's own
/// convention of soft-failing to void/no-collision rather than erroring, so
/// a host only implements what it actually supports — including no host at
/// all, which makes every Director-specific opcode degrade the same way.
public protocol LingoVMHost: AnyObject {
    var movie: LingoObject { get }
    func sprite(_ channel: LingoValue) -> LingoObject?
    func member(_ id: LingoValue, castLib: LingoValue?) -> LingoObject?
    func menu(_ id: LingoValue) -> LingoObject?
    func sound(_ id: LingoValue) -> LingoObject?
    func window(_ id: LingoValue) -> LingoObject?
    func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject?
    func spriteIntersects(_ a: LingoObject, _ b: LingoObject) -> Bool
    func spriteWithin(_ a: LingoObject, _ b: LingoObject) -> Bool
    /// Highlights `type` (char/word/item/line) range `first...last` within
    /// a live field member — the one Director-specific side effect
    /// `hiliteChunk` needs that neither `LingoObject` nor `LingoEnvironment`
    /// can express, since it's a UI effect with no corresponding property.
    func hilite(_ member: LingoObject, type: String, first: LingoValue, last: LingoValue)
}

extension LingoVMHost {
    public func sprite(_ channel: LingoValue) -> LingoObject? { nil }
    public func member(_ id: LingoValue, castLib: LingoValue?) -> LingoObject? { nil }
    public func menu(_ id: LingoValue) -> LingoObject? { nil }
    public func sound(_ id: LingoValue) -> LingoObject? { nil }
    public func window(_ id: LingoValue) -> LingoObject? { nil }
    public func makeObject(scriptName: String, args: [LingoValue]) -> LingoObject? { nil }
    public func spriteIntersects(_ a: LingoObject, _ b: LingoObject) -> Bool { false }
    public func spriteWithin(_ a: LingoObject, _ b: LingoObject) -> Bool { false }
    public func hilite(_ member: LingoObject, type: String, first: LingoValue, last: LingoValue) {}
}
