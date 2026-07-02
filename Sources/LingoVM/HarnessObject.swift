import LingoRuntime

/// A generic property-bag `LingoObject` for exercising `LingoVM` without a
/// real Director object model behind it — usable directly (as a plain
/// receiver, sprite, member, or window) or subclassed for something more
/// specific.
///
/// Unlike a minimal test double that overrides `getProperty`/`callMethod`
/// and never calls `super`, this class falls through to the base
/// implementation on a miss — so a `HarnessObject` participates fully in
/// `LingoObject`'s ancestor-chain property/method inheritance and
/// global-function fallback, not a shortcut around them.
open class HarnessObject: LingoObject {
    public var properties: [String: LingoValue] = [:]
    public var methods: [String: ([LingoValue]) -> LingoValue] = [:]
    public private(set) var lastMethodCall: (name: String, args: [LingoValue])?

    open override func getProperty(_ name: String) -> LingoValue {
        properties[name] ?? super.getProperty(name)
    }

    open override func setProperty(_ name: String, value: LingoValue) {
        properties[name] = value
    }

    open override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
        lastMethodCall = (name, args)
        if let handler = methods[name] {
            return handler(args)
        }
        return super.callMethod(name, args: args)
    }
}
