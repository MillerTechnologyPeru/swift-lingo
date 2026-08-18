import Testing

@testable import LingoRuntime

/// Compiled Lingo calls the language's own functions by name, and an
/// unregistered name evaluates to VOID instead of failing — so a missing
/// builtin reads as the script choosing to do nothing. `repeat with x in
/// list` is the case that hurts: it lowers to `count(list)` plus
/// `getAt(list, i)`, both in their function spelling.
@Suite("Standard Lingo Builtins")
struct StandardBuiltinTests {

    private let environment = LingoEnvironment()

    private func call(_ name: String, _ args: LingoValue...) -> LingoValue {
        environment.callGlobal(name, args: args)
    }

    // MARK: The `repeat with x in list` lowering

    @Test func countAnswersListLength() {
        #expect(call("count", .list([.integer(1), .integer(2)])).asInteger() == 2)
        #expect(
            call("count", .propertyList([(key: .symbol("a"), value: .integer(1))])).asInteger() == 1
        )
    }

    @Test func getAtWorksInItsFunctionSpelling() {
        let list = LingoValue.list([.symbol("first"), .symbol("second")])
        #expect(call("getAt", list, .integer(2)).asString() == "second")
    }

    @Test func getAtReadsAPropertyListByKey() {
        let list = LingoValue.propertyList([(key: .symbol("k"), value: .integer(5))])
        #expect(call("getAt", list, .symbol("k")).asInteger() == 5)
    }

    @Test func listCommandsMutateInTheirFunctionSpelling() {
        let list = LingoValue.list([.integer(1)])
        _ = call("add", list, .integer(2))
        #expect(call("count", list).asInteger() == 2)
        _ = call("deleteOne", list, .integer(1))
        #expect(call("getAt", list, .integer(1)).asInteger() == 2)
    }

    @Test func listFunctionsIgnoreNonLists() {
        if case .void = call("getAt", .integer(3), .integer(1)) {
        } else {
            Issue.record("expected VOID for a non-list receiver")
        }
    }

    // MARK: Type inspection

    @Test func voidpDetectsVoid() {
        #expect(call("voidp", .void).asInteger() == 1)
        #expect(call("voidp", .integer(0)).asInteger() == 0)
    }

    @Test func ilkNamesTheType() {
        #expect(call("ilk", .list([])).asString() == "list")
        #expect(call("ilk", .propertyList([])).asString() == "propList")
        #expect(call("ilk", .string("x")).asString() == "string")
        #expect(call("ilk", .void).asString() == "void")
    }

    @Test func ilkWithATypeAsksInstead() {
        #expect(call("ilk", .list([]), .symbol("list")).asInteger() == 1)
        #expect(call("ilk", .string("x"), .symbol("list")).asInteger() == 0)
        // A property list answers to #list as well, as Lingo reports it.
        #expect(call("ilk", .propertyList([]), .symbol("list")).asInteger() == 1)
    }

    @Test func predicatesClassifyValues() {
        #expect(call("listP", .list([])).asInteger() == 1)
        #expect(call("stringP", .string("a")).asInteger() == 1)
        #expect(call("symbolP", .symbol("a")).asInteger() == 1)
        #expect(call("integerP", .integer(1)).asInteger() == 1)
        #expect(call("floatP", .float(1.5)).asInteger() == 1)
        #expect(call("listP", .integer(1)).asInteger() == 0)
    }

    // MARK: Coercions and arithmetic

    @Test func pointAndRectAreListsWithNamedComponents() {
        let p = call("point", .integer(3), .integer(4))
        #expect(p.count.asInteger() == 2)
        #expect(p[.integer(1)].asInteger() == 3)
        #expect(LingoBuiltins.geometryProperty(of: p, named: "locV")?.asInteger() == 4)

        let r = call("rect", .integer(10), .integer(20), .integer(110), .integer(70))
        #expect(LingoBuiltins.geometryProperty(of: r, named: "right")?.asInteger() == 110)
        #expect(LingoBuiltins.geometryProperty(of: r, named: "width")?.asInteger() == 100)
        #expect(LingoBuiltins.geometryProperty(of: r, named: "height")?.asInteger() == 50)
        let r2 = call("rect", p, call("point", .integer(13), .integer(24)))
        #expect(LingoBuiltins.geometryProperty(of: r2, named: "width")?.asInteger() == 10)
        #expect(LingoBuiltins.geometryProperty(of: r2, named: "bottom")?.asInteger() == 24)
        // Not a component of a two-element list, and never of a non-list.
        #expect(LingoBuiltins.geometryProperty(of: p, named: "left") == nil)
        #expect(LingoBuiltins.geometryProperty(of: .integer(1), named: "locH") == nil)
    }

    @Test func valueReadsListLiterals() {
        let list = call("value", .string("[1, \"two\", #three]"))
        #expect(list.count.asInteger() == 3)
        #expect(list[.integer(2)].asString() == "two")
        #expect(list[.integer(3)].asString() == "three")

        // The shape a behavior initializer takes in the score.
        let plist = call("value", .string("[#mylocz: 5, #label: \"a, b\"]"))
        #expect(plist.listGetAProp(.symbol("mylocz")).asInteger() == 5)
        #expect(plist.listGetAProp(.symbol("label")).asString() == "a, b")

        let nested = call("value", .string("[#loc: [10, -20], #empty: [:], #none: []]"))
        #expect(nested.listGetAProp(.symbol("loc"))[.integer(2)].asInteger() == -20)
        #expect(nested.listGetAProp(.symbol("empty")).count.asInteger() == 0)
        #expect(nested.listGetAProp(.symbol("none")).count.asInteger() == 0)

        // Not literals: an expression, trailing junk, a bare word.
        for text in ["1 + 2", "[1, 2] x", "hello", "[#a: 1, 2]"] {
            if case .void = call("value", .string(text)) {
            } else {
                Issue.record("expected VOID for \(text)")
            }
        }
    }

    @Test func valueParsesNumbersOutOfStrings() {
        #expect(call("value", .string(" 42 ")).asInteger() == 42)
        if case .float(let d) = call("value", .string("1.5")) {
            #expect(d == 1.5)
        } else {
            Issue.record("expected a float")
        }
        if case .void = call("value", .string("nonsense")) {
        } else {
            Issue.record("expected VOID for unparseable text")
        }
    }

    @Test func absAndExtremesWork() {
        #expect(call("abs", .integer(-4)).asInteger() == 4)
        #expect(call("max", .integer(2), .integer(9), .integer(5)).asInteger() == 9)
        #expect(call("min", .integer(2), .integer(9)).asInteger() == 2)
        // A single list argument is treated as the set of values.
        #expect(call("max", .list([.integer(3), .integer(7)])).asInteger() == 7)
    }

    /// A host has to be able to give a builtin its own behavior.
    @Test func aHostCanOverrideABuiltin() {
        environment.registerGlobalFunction("count") { _ in .integer(99) }
        #expect(call("count", .list([.integer(1)])).asInteger() == 99)
    }
}

@Suite("String Builtins")
struct StringBuiltinTests {

    private let environment = LingoEnvironment()

    private func call(_ name: String, _ args: LingoValue...) -> LingoValue {
        environment.callGlobal(name, args: args)
    }

    /// `repeat while offset(numToChar(10), t) > 0` is the pattern that
    /// makes these load-bearing: the junkbot config manager strips line
    /// feeds with exactly that loop, and with `offset` unregistered the
    /// VOID result kept the loop from ever terminating.
    @Test func offsetFindsSubstringsOneBased() {
        #expect(call("offset", .string("b"), .string("abc")).asInteger() == 2)
        #expect(call("offset", .string("abc"), .string("abc")).asInteger() == 1)
        #expect(call("offset", .string("z"), .string("abc")).asInteger() == 0)
        #expect(call("offset", .string(""), .string("abc")).asInteger() == 0)
        #expect(call("offset", .string("B"), .string("abc")).asInteger() == 2)
    }

    @Test func numToCharAndBackRoundTrip() {
        #expect(call("numToChar", .integer(65)).asString() == "A")
        #expect(call("numToChar", .integer(13)).asString() == "\r")
        #expect(call("charToNum", .string("A")).asInteger() == 65)
        #expect(call("charToNum", .string("")).asInteger() == 0)
    }

    @Test func lengthCountsCharacters() {
        #expect(call("length", .string("abc")).asInteger() == 3)
        #expect(call("length", .string("")).asInteger() == 0)
        #expect(call("length", .integer(5)).asInteger() == 0)
    }

    @Test func charsSlicesInclusively() {
        #expect(call("chars", .string("abcdef"), .integer(2), .integer(4)).asString() == "bcd")
        #expect(call("chars", .string("abc"), .integer(2), .integer(99)).asString() == "bc")
        #expect(call("chars", .string("abc"), .integer(3), .integer(1)).asString() == "")
    }
}

/// The builtins are plain Swift functions too — hosts and other builtins
/// call them without going through name dispatch.
@Suite("Direct Builtin Calls")
struct DirectBuiltinCallTests {

    @Test func builtinsAreCallableWithoutAnEnvironment() {
        #expect(LingoBuiltins.count(.list([.integer(1), .integer(2)])).asInteger() == 2)
        #expect(LingoBuiltins.voidP(.void).asInteger() == 1)
        #expect(LingoBuiltins.offset(.string("b"), .string("abc")).asInteger() == 2)
        #expect(LingoBuiltins.numToChar(.integer(65)).asString() == "A")
        #expect(LingoBuiltins.ilk(.list([])).asString() == "list")
        #expect(LingoBuiltins.ilk(.list([]), .symbol("list")).asInteger() == 1)
        #expect(
            LingoBuiltins.chars(.string("abcdef"), .integer(2), .integer(4)).asString() == "bcd")
        #expect(LingoBuiltins.max([.integer(2), .integer(9), .integer(5)]).asInteger() == 9)
    }

    /// The registered spellings and the Swift functions are the same code:
    /// answers agree by construction.
    @Test func registeredNamesDelegateToTheSwiftFunctions() {
        let environment = LingoEnvironment()
        let viaName = environment.callGlobal(
            "offset", args: [.string("wörld"), .string("héllo wörld")])
        let direct = LingoBuiltins.offset(.string("wörld"), .string("héllo wörld"))
        #expect(LingoValue.equalsBool(lhs: viaName, rhs: direct))
        #expect(direct.asInteger() == 7)
    }
}

/// The numeric-or-keep-string idiom real parsers rely on:
/// `v = float(v)` then `if integer(v) = v then v = integer(v)` leaves
/// numeric strings as numbers and everything else as the original string.
@Suite("Coercion Semantics")
struct CoercionSemanticsTests {

    @Test func floatKeepsNonNumericStringsUnchanged() {
        #expect(LingoBuiltins.float(.string("demo")).asString() == "demo")
        if case .string = LingoBuiltins.float(.string("demo")) {
        } else {
            Issue.record("float of a non-numeric string must stay a string")
        }
        if case .float(let d) = LingoBuiltins.float(.string(" 3.5 ")) {
            #expect(d == 3.5)
        } else {
            Issue.record("float should parse numeric strings")
        }
    }

    @Test func integerRoundsAndParsesOrIsVoid() {
        #expect(LingoBuiltins.integer(.float(3.7)).asInteger() == 4)
        #expect(LingoBuiltins.integer(.float(-2.5)).asInteger() == -3)  // half away from zero, like the reference
        #expect(LingoBuiltins.integer(.string("42")).asInteger() == 42)
        if case .void = LingoBuiltins.integer(.string("demo")) {
        } else {
            Issue.record("integer of a non-numeric string must be VOID")
        }
    }

    @Test func theNumericOrKeepStringIdiomWorks() {
        for (input, expectNumeric) in [("3", true), ("0", true), ("demo", false), ("35;21", false)] {
            var value = LingoBuiltins.float(.string(input))
            let asInt = LingoBuiltins.integer(value)
            if LingoValue.equalsBool(lhs: asInt, rhs: value) {
                value = asInt
            }
            if expectNumeric {
                if case .integer = value {} else { Issue.record("\(input) should become a number") }
            } else {
                #expect(value.asString() == input, "\(input) should stay itself")
            }
        }
    }
}
