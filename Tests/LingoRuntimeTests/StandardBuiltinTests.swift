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
