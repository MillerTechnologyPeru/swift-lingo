import Testing

@testable import LingoRuntime

/// A minimal `LingoObject` whose own declared properties/methods are backed
/// by plain dictionaries, falling through to `super` (the ancestor-chain
/// walk) for anything it doesn't recognize itself — the same shape a
/// transpiler-generated script class has.
private final class Widget: LingoObject {
    var properties: [String: LingoValue] = [:]
    var methods: Set<String> = []

    override func getProperty(_ name: String) -> LingoValue {
        guard let value = properties[name] else { return super.getProperty(name) }
        return value
    }

    override func setProperty(_ name: String, value: LingoValue) {
        properties[name] = value
    }

    override func callMethod(_ name: String, args: [LingoValue]) -> LingoValue {
        guard methods.contains(name) else { return super.callMethod(name, args: args) }
        return .string("\(name):\(args.count)")
    }
}

@Test func getPropertyWithNoAncestorReturnsVoid() {
    let widget = Widget(environment: LingoEnvironment())
    #expect(LingoValue.equalsBool(lhs: widget.getProperty("color"), rhs: .void))
}

@Test func getPropertyInheritsFromAncestor() {
    let environment = LingoEnvironment()
    let ancestor = Widget(environment: environment)
    ancestor.properties["color"] = .string("red")

    let child = Widget(environment: environment)
    child.properties["ancestor"] = .object(ancestor)

    #expect(LingoValue.equalsBool(lhs: child.getProperty("color"), rhs: .string("red")))
}

@Test func getPropertyOnChildTakesPriorityOverAncestor() {
    let environment = LingoEnvironment()
    let ancestor = Widget(environment: environment)
    ancestor.properties["color"] = .string("red")

    let child = Widget(environment: environment)
    child.properties["ancestor"] = .object(ancestor)
    child.properties["color"] = .string("blue")

    #expect(LingoValue.equalsBool(lhs: child.getProperty("color"), rhs: .string("blue")))
}

@Test func getPropertyWalksMultipleAncestorLinks() {
    let environment = LingoEnvironment()
    let grandparent = Widget(environment: environment)
    grandparent.properties["size"] = .integer(42)

    let parent = Widget(environment: environment)
    parent.properties["ancestor"] = .object(grandparent)

    let child = Widget(environment: environment)
    child.properties["ancestor"] = .object(parent)

    #expect(LingoValue.equalsBool(lhs: child.getProperty("size"), rhs: .integer(42)))
}

@Test func getPropertyMissingEverywhereReturnsVoid() {
    let environment = LingoEnvironment()
    let ancestor = Widget(environment: environment)
    let child = Widget(environment: environment)
    child.properties["ancestor"] = .object(ancestor)

    #expect(LingoValue.equalsBool(lhs: child.getProperty("nonexistent"), rhs: .void))
}

@Test func callMethodInheritsFromAncestor() {
    let environment = LingoEnvironment()
    let ancestor = Widget(environment: environment)
    ancestor.methods.insert("greet")

    let child = Widget(environment: environment)
    child.properties["ancestor"] = .object(ancestor)

    #expect(
        LingoValue.equalsBool(
            lhs: child.callMethod("greet", args: [.integer(1)]), rhs: .string("greet:1")))
}

@Test func callMethodOnChildTakesPriorityOverAncestor() {
    let environment = LingoEnvironment()
    let ancestor = Widget(environment: environment)
    ancestor.methods.insert("greet")

    let child = Widget(environment: environment)
    child.properties["ancestor"] = .object(ancestor)
    child.methods.insert("greet")

    #expect(LingoValue.equalsBool(lhs: child.callMethod("greet", args: []), rhs: .string("greet:0")))
}

@Test func callMethodFallsThroughToGlobalWhenNoAncestorRecognizesIt() {
    let environment = LingoEnvironment()
    environment.registerGlobalFunction("beep") { _ in .integer(99) }

    let ancestor = Widget(environment: environment)
    let child = Widget(environment: environment)
    child.properties["ancestor"] = .object(ancestor)

    #expect(LingoValue.equalsBool(lhs: child.callMethod("beep", args: []), rhs: .integer(99)))
}

@Test func ancestorChainDoesNotLoopForeverOnASelfCycle() {
    // A malformed script that sets its own ancestor to itself must still
    // terminate rather than loop forever.
    let environment = LingoEnvironment()
    let widget = Widget(environment: environment)
    widget.properties["ancestor"] = .object(widget)

    #expect(LingoValue.equalsBool(lhs: widget.getProperty("color"), rhs: .void))
}

@Test func ancestorChainDoesNotLoopForeverOnATwoObjectCycle() {
    // Same as the self-cycle case, but the cycle spans two distinct objects
    // (a > ancestor > b > ancestor > a), which a naive "have I seen myself"
    // check wouldn't catch.
    let environment = LingoEnvironment()
    let a = Widget(environment: environment)
    let b = Widget(environment: environment)
    a.properties["ancestor"] = .object(b)
    b.properties["ancestor"] = .object(a)

    #expect(LingoValue.equalsBool(lhs: a.getProperty("color"), rhs: .void))
    #expect(LingoValue.equalsBool(lhs: a.callMethod("greet", args: []), rhs: .void))
}
