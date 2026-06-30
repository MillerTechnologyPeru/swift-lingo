import Testing
@testable import LingoRuntime

// MARK: - String Extension Tests

@Suite("String Case-Insensitive Operations")
struct StringExtensionTests {

    // MARK: caseInsensitiveEquals

    @Test func equalsIdenticalStrings() {
        #expect("hello".caseInsensitiveEquals("hello"))
    }

    @Test func equalsDifferentCase() {
        #expect("Hello".caseInsensitiveEquals("hELLO"))
    }

    @Test func equalsAllCaps() {
        #expect("ABC".caseInsensitiveEquals("abc"))
    }

    @Test func equalsEmptyStrings() {
        #expect("".caseInsensitiveEquals(""))
    }

    @Test func equalsDifferentLengths() {
        #expect(!"hello".caseInsensitiveEquals("hell"))
    }

    @Test func equalsDifferentContent() {
        #expect(!"hello".caseInsensitiveEquals("world"))
    }

    @Test func equalsWithNumbers() {
        #expect("abc123".caseInsensitiveEquals("ABC123"))
    }

    // MARK: caseInsensitiveLessThan

    @Test func lessThanAlphabetical() {
        #expect("abc".caseInsensitiveLessThan("def"))
    }

    @Test func lessThanCaseInsensitive() {
        #expect("ABC".caseInsensitiveLessThan("def"))
    }

    @Test func lessThanReversed() {
        #expect(!"def".caseInsensitiveLessThan("abc"))
    }

    @Test func lessThanEqual() {
        #expect(!"abc".caseInsensitiveLessThan("ABC"))
    }

    @Test func lessThanShorterPrefix() {
        #expect("ab".caseInsensitiveLessThan("abc"))
    }

    @Test func lessThanLongerNotLess() {
        #expect(!"abc".caseInsensitiveLessThan("ab"))
    }

    @Test func lessThanEmpty() {
        #expect("".caseInsensitiveLessThan("a"))
        #expect(!"a".caseInsensitiveLessThan(""))
    }

    // MARK: caseInsensitiveContains

    @Test func containsSubstring() {
        #expect("Hello World".caseInsensitiveContains("llo wo"))
    }

    @Test func containsCaseInsensitive() {
        #expect("Hello World".caseInsensitiveContains("HELLO"))
    }

    @Test func containsAtEnd() {
        #expect("Hello World".caseInsensitiveContains("WORLD"))
    }

    @Test func containsEmpty() {
        #expect("Hello".caseInsensitiveContains(""))
    }

    @Test func containsNoMatch() {
        #expect(!"Hello".caseInsensitiveContains("xyz"))
    }

    @Test func containsLongerSubstring() {
        #expect(!"Hi".caseInsensitiveContains("Hello"))
    }

    @Test func containsExactMatch() {
        #expect("Hello".caseInsensitiveContains("Hello"))
    }

    // MARK: caseInsensitiveStartsWith

    @Test func startsWithPrefix() {
        #expect("Hello World".caseInsensitiveStartsWith("hello"))
    }

    @Test func startsWithFullMatch() {
        #expect("Hello".caseInsensitiveStartsWith("HELLO"))
    }

    @Test func startsWithEmpty() {
        #expect("Hello".caseInsensitiveStartsWith(""))
    }

    @Test func startsWithNoMatch() {
        #expect(!"Hello".caseInsensitiveStartsWith("World"))
    }

    @Test func startsWithLongerPrefix() {
        #expect(!"Hi".caseInsensitiveStartsWith("Hello"))
    }
}

// MARK: - LingoValue Equality & Comparison Tests

@Suite("LingoValue Equality")
struct LingoValueEqualityTests {

    @Test func voidEqualsVoid() {
        #expect(LingoValue.equalsBool(lhs: .void, rhs: .void))
    }

    @Test func integerEquality() {
        #expect(LingoValue.equalsBool(lhs: .integer(42), rhs: .integer(42)))
        #expect(!LingoValue.equalsBool(lhs: .integer(1), rhs: .integer(2)))
    }

    @Test func floatEquality() {
        #expect(LingoValue.equalsBool(lhs: .float(3.14), rhs: .float(3.14)))
        #expect(!LingoValue.equalsBool(lhs: .float(1.0), rhs: .float(2.0)))
    }

    @Test func intFloatMixedEquality() {
        #expect(LingoValue.equalsBool(lhs: .integer(5), rhs: .float(5.0)))
        #expect(LingoValue.equalsBool(lhs: .float(5.0), rhs: .integer(5)))
        #expect(!LingoValue.equalsBool(lhs: .integer(5), rhs: .float(5.1)))
    }

    @Test func stringCaseInsensitiveEquality() {
        #expect(LingoValue.equalsBool(lhs: .string("Hello"), rhs: .string("hello")))
        #expect(LingoValue.equalsBool(lhs: .string("ABC"), rhs: .string("abc")))
        #expect(!LingoValue.equalsBool(lhs: .string("abc"), rhs: .string("xyz")))
    }

    @Test func symbolEquality() {
        #expect(LingoValue.equalsBool(lhs: .symbol("foo"), rhs: .symbol("FOO")))
    }

    @Test func symbolStringCrossEquality() {
        #expect(LingoValue.equalsBool(lhs: .symbol("test"), rhs: .string("TEST")))
        #expect(LingoValue.equalsBool(lhs: .string("test"), rhs: .symbol("TEST")))
    }

    @Test func deepListEquality() {
        let a: LingoValue = .list([.integer(1), .string("Hello")])
        let b: LingoValue = .list([.integer(1), .string("hello")])
        let c: LingoValue = .list([.integer(1), .string("world")])
        #expect(LingoValue.equalsBool(lhs: a, rhs: b))
        #expect(!LingoValue.equalsBool(lhs: a, rhs: c))
    }

    @Test func listDifferentLengths() {
        let a: LingoValue = .list([.integer(1)])
        let b: LingoValue = .list([.integer(1), .integer(2)])
        #expect(!LingoValue.equalsBool(lhs: a, rhs: b))
    }

    @Test func deepPropertyListEquality() {
        let a: LingoValue = .propertyList([
            (key: .symbol("x"), value: .integer(10)),
            (key: .symbol("y"), value: .integer(20))
        ])
        let b: LingoValue = .propertyList([
            (key: .symbol("X"), value: .integer(10)),
            (key: .symbol("Y"), value: .integer(20))
        ])
        #expect(LingoValue.equalsBool(lhs: a, rhs: b))
    }

    @Test func mismatchedTypesNotEqual() {
        #expect(!LingoValue.equalsBool(lhs: .integer(1), rhs: .string("1")))
        #expect(!LingoValue.equalsBool(lhs: .void, rhs: .integer(0)))
    }
}

@Suite("LingoValue Relational Operators")
struct LingoValueRelationalTests {

    @Test func lessThanIntegers() {
        #expect(LingoValue.lessThanBool(lhs: .integer(1), rhs: .integer(2)))
        #expect(!LingoValue.lessThanBool(lhs: .integer(2), rhs: .integer(1)))
        #expect(!LingoValue.lessThanBool(lhs: .integer(2), rhs: .integer(2)))
    }

    @Test func lessThanFloats() {
        #expect(LingoValue.lessThanBool(lhs: .float(1.0), rhs: .float(2.0)))
        #expect(!LingoValue.lessThanBool(lhs: .float(2.0), rhs: .float(1.0)))
    }

    @Test func lessThanMixed() {
        #expect(LingoValue.lessThanBool(lhs: .integer(1), rhs: .float(1.5)))
        #expect(LingoValue.lessThanBool(lhs: .float(0.5), rhs: .integer(1)))
    }

    @Test func lessThanStrings() {
        #expect(LingoValue.lessThanBool(lhs: .string("abc"), rhs: .string("DEF")))
        #expect(!LingoValue.lessThanBool(lhs: .string("DEF"), rhs: .string("abc")))
    }

    // MARK: LingoValue-returning operators

    @Test func equalityOperatorReturnsLingoValue() {
        let result: LingoValue = .integer(5) == .integer(5)
        #expect(result.asBool())
        let result2: LingoValue = .integer(5) == .integer(6)
        #expect(!result2.asBool())
    }

    @Test func notEqualOperator() {
        let result: LingoValue = .integer(5) != .integer(6)
        #expect(result.asBool())
        let result2: LingoValue = .integer(5) != .integer(5)
        #expect(!result2.asBool())
    }

    @Test func lessThanOperatorReturnsLingoValue() {
        let result: LingoValue = .integer(1) < .integer(2)
        #expect(result.asBool())
    }

    @Test func greaterThanOperator() {
        let result: LingoValue = .integer(3) > .integer(2)
        #expect(result.asBool())
        let result2: LingoValue = .integer(2) > .integer(3)
        #expect(!result2.asBool())
        let result3: LingoValue = .integer(2) > .integer(2)
        #expect(!result3.asBool())
    }

    @Test func lessThanOrEqualOperator() {
        let result: LingoValue = .integer(2) <= .integer(2)
        #expect(result.asBool())
        let result2: LingoValue = .integer(1) <= .integer(2)
        #expect(result2.asBool())
        let result3: LingoValue = .integer(3) <= .integer(2)
        #expect(!result3.asBool())
    }

    @Test func greaterThanOrEqualOperator() {
        let result: LingoValue = .integer(2) >= .integer(2)
        #expect(result.asBool())
        let result2: LingoValue = .integer(3) >= .integer(2)
        #expect(result2.asBool())
        let result3: LingoValue = .integer(1) >= .integer(2)
        #expect(!result3.asBool())
    }
}

// MARK: - LingoValue Arithmetic Tests

@Suite("LingoValue Arithmetic")
struct LingoValueArithmeticTests {

    @Test func addIntegers() {
        let result: LingoValue = .integer(2) + .integer(3)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(5)))
    }

    @Test func addFloats() {
        let result: LingoValue = .float(1.5) + .float(2.5)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .float(4.0)))
    }

    @Test func addIntFloat() {
        let result: LingoValue = .integer(2) + .float(3.5)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .float(5.5)))
    }

    @Test func addStrings() {
        let result: LingoValue = .string("hello ") + .string("world")
        #expect(LingoValue.equalsBool(lhs: result, rhs: .string("hello world")))
    }

    @Test func subtractIntegers() {
        let result: LingoValue = .integer(10) - .integer(3)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(7)))
    }

    @Test func multiplyIntegers() {
        let result: LingoValue = .integer(4) * .integer(5)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(20)))
    }

    @Test func divideIntegers() {
        let result: LingoValue = .integer(10) / .integer(3)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .integer(3)))
    }

    @Test func divideByZeroReturnsVoid() {
        let result: LingoValue = .integer(10) / .integer(0)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
    }

    @Test func mismatchedArithmeticReturnsVoid() {
        let result: LingoValue = .integer(1) + .string("x")
        #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
    }
}

// MARK: - LingoValue asBool Tests

@Suite("LingoValue asBool")
struct LingoValueAsBoolTests {

    @Test func integerTruthy() {
        #expect(LingoValue.integer(1).asBool())
        #expect(LingoValue.integer(-1).asBool())
    }

    @Test func integerFalsy() {
        #expect(!LingoValue.integer(0).asBool())
    }

    @Test func floatTruthy() {
        #expect(LingoValue.float(0.1).asBool())
    }

    @Test func floatFalsy() {
        #expect(!LingoValue.float(0).asBool())
    }

    @Test func stringTrue() {
        #expect(LingoValue.string("true").asBool())
        #expect(LingoValue.string("TRUE").asBool())
        #expect(LingoValue.string("True").asBool())
    }

    @Test func stringFalse() {
        #expect(!LingoValue.string("false").asBool())
        #expect(!LingoValue.string("").asBool())
        #expect(!LingoValue.string("hello").asBool())
    }

    @Test func voidIsFalsy() {
        #expect(!LingoValue.void.asBool())
    }

    @Test func listIsTruthy() {
        #expect(LingoValue.list([]).asBool())
    }
}

// MARK: - LingoValue Indexing Tests (1-based)

@Suite("LingoValue 1-based Indexing")
struct LingoValueIndexingTests {

    @Test func listIndexOneBased() {
        let list: LingoValue = .list([.integer(10), .integer(20), .integer(30)])
        #expect(LingoValue.equalsBool(lhs: list[.integer(1)], rhs: .integer(10)))
        #expect(LingoValue.equalsBool(lhs: list[.integer(2)], rhs: .integer(20)))
        #expect(LingoValue.equalsBool(lhs: list[.integer(3)], rhs: .integer(30)))
    }

    @Test func listIndexOutOfBounds() {
        let list: LingoValue = .list([.integer(10)])
        #expect(LingoValue.equalsBool(lhs: list[.integer(0)], rhs: .void))
        #expect(LingoValue.equalsBool(lhs: list[.integer(2)], rhs: .void))
    }

    @Test func propertyListIndexOneBased() {
        let plist: LingoValue = .propertyList([
            (key: .symbol("a"), value: .integer(1)),
            (key: .symbol("b"), value: .integer(2))
        ])
        #expect(LingoValue.equalsBool(lhs: plist[.integer(1)], rhs: .integer(1)))
        #expect(LingoValue.equalsBool(lhs: plist[.integer(2)], rhs: .integer(2)))
    }

    @Test func propertyListKeyLookup() {
        let plist: LingoValue = .propertyList([
            (key: .symbol("name"), value: .string("Junkbot")),
            (key: .symbol("level"), value: .integer(5))
        ])
        #expect(LingoValue.equalsBool(lhs: plist[.symbol("name")], rhs: .string("Junkbot")))
        #expect(LingoValue.equalsBool(lhs: plist[.symbol("level")], rhs: .integer(5)))
    }

    @Test func propertyListKeyLookupCaseInsensitive() {
        let plist: LingoValue = .propertyList([
            (key: .symbol("Name"), value: .string("test"))
        ])
        #expect(LingoValue.equalsBool(lhs: plist[.symbol("name")], rhs: .string("test")))
    }

    @Test func stringIndexOneBased() {
        let s: LingoValue = .string("Hello")
        #expect(LingoValue.equalsBool(lhs: s[.integer(1)], rhs: .string("H")))
        #expect(LingoValue.equalsBool(lhs: s[.integer(5)], rhs: .string("o")))
    }

    @Test func stringIndexOutOfBounds() {
        let s: LingoValue = .string("Hi")
        #expect(LingoValue.equalsBool(lhs: s[.integer(0)], rhs: .void))
        #expect(LingoValue.equalsBool(lhs: s[.integer(3)], rhs: .void))
    }
}

// MARK: - LingoValue setElement Tests

@Suite("LingoValue setElement")
struct LingoValueSetElementTests {

    @Test func setListElement() {
        let list: LingoValue = .list([.integer(1), .integer(2), .integer(3)])
        list.setElement(index: .integer(2), value: .integer(99))
        #expect(LingoValue.equalsBool(lhs: list[.integer(2)], rhs: .integer(99)))
    }

    @Test func setListElementOutOfBounds() {
        let list: LingoValue = .list([.integer(1)])
        list.setElement(index: .integer(5), value: .integer(99))
        // Should be unchanged
        #expect(LingoValue.equalsBool(lhs: list[.integer(1)], rhs: .integer(1)))
    }

    @Test func setPropertyListByIndex() {
        let plist: LingoValue = .propertyList([
            (key: .symbol("a"), value: .integer(1)),
            (key: .symbol("b"), value: .integer(2))
        ])
        plist.setElement(index: .integer(1), value: .integer(99))
        #expect(LingoValue.equalsBool(lhs: plist[.integer(1)], rhs: .integer(99)))
    }

    @Test func setPropertyListByKey() {
        let plist: LingoValue = .propertyList([
            (key: .symbol("name"), value: .string("old"))
        ])
        plist.setElement(index: .symbol("name"), value: .string("new"))
        #expect(LingoValue.equalsBool(lhs: plist[.symbol("name")], rhs: .string("new")))
    }

    @Test func setPropertyListNewKey() {
        let plist: LingoValue = .propertyList([
            (key: .symbol("a"), value: .integer(1))
        ])
        plist.setElement(index: .symbol("b"), value: .integer(2))
        #expect(LingoValue.equalsBool(lhs: plist[.symbol("b")], rhs: .integer(2)))
    }
}

// MARK: - LingoValue String Range Tests

@Suite("LingoValue String Ranges")
struct LingoValueStringRangeTests {

    @Test func getRange1Based() {
        let s: LingoValue = .string("Hello World")
        let result = s.getRange(start: .integer(1), end: .integer(5))
        #expect(LingoValue.equalsBool(lhs: result, rhs: .string("Hello")))
    }

    @Test func getRange1BasedMiddle() {
        let s: LingoValue = .string("Hello World")
        let result = s.getRange(start: .integer(7), end: .integer(11))
        #expect(LingoValue.equalsBool(lhs: result, rhs: .string("World")))
    }

    @Test func getRange1BasedSingleChar() {
        let s: LingoValue = .string("Hello")
        let result = s.getRange(start: .integer(3), end: .integer(3))
        #expect(LingoValue.equalsBool(lhs: result, rhs: .string("l")))
    }

    @Test func getRange0Based() {
        let s: LingoValue = .string("Hello World")
        let result = s.getRange(start: 0, end: 5)
        #expect(LingoValue.equalsBool(lhs: result, rhs: .string("Hello")))
    }

    @Test func getRangeOnNonString() {
        let v: LingoValue = .integer(42)
        let result = v.getRange(start: .integer(1), end: .integer(3))
        #expect(LingoValue.equalsBool(lhs: result, rhs: .void))
    }

    @Test func getRangeClampsBounds() {
        let s: LingoValue = .string("Hi")
        let result = s.getRange(start: .integer(1), end: .integer(100))
        #expect(LingoValue.equalsBool(lhs: result, rhs: .string("Hi")))
    }
}

// MARK: - LingoValue Utilities Tests

@Suite("LingoValue Utilities")
struct LingoValueUtilitiesTests {

    @Test func stringContainsSubstring() {
        let s: LingoValue = .string("Hello World")
        #expect(s.contains(.string("WORLD")).asBool())
    }

    @Test func stringNotContains() {
        let s: LingoValue = .string("Hello World")
        #expect(!s.contains(.string("xyz")).asBool())
    }

    @Test func listContainsElement() {
        let list: LingoValue = .list([.integer(1), .string("hello"), .integer(3)])
        #expect(list.contains(.string("HELLO")).asBool())
        #expect(list.contains(.integer(3)).asBool())
    }

    @Test func listNotContains() {
        let list: LingoValue = .list([.integer(1)])
        #expect(!list.contains(.integer(99)).asBool())
    }

    @Test func stringStartsWith() {
        let s: LingoValue = .string("Hello World")
        #expect(s.starts(with: .string("HELLO")).asBool())
    }

    @Test func stringNotStartsWith() {
        let s: LingoValue = .string("Hello World")
        #expect(!s.starts(with: .string("World")).asBool())
    }
}

// MARK: - LingoValue Collection Conformance Tests

@Suite("LingoValue RandomAccessCollection")
struct LingoValueCollectionTests {

    @Test func listZeroBasedSubscript() {
        let list: LingoValue = .list([.integer(10), .integer(20), .integer(30)])
        #expect(LingoValue.equalsBool(lhs: list[0], rhs: .integer(10)))
        #expect(LingoValue.equalsBool(lhs: list[1], rhs: .integer(20)))
        #expect(LingoValue.equalsBool(lhs: list[2], rhs: .integer(30)))
    }

    @Test func listMutableSubscript() {
        var list: LingoValue = .list([.integer(1), .integer(2)])
        list[0] = .integer(99)
        #expect(LingoValue.equalsBool(lhs: list[0], rhs: .integer(99)))
    }

    @Test func propertyListZeroBasedSubscript() {
        let plist: LingoValue = .propertyList([
            (key: .symbol("a"), value: .integer(1)),
            (key: .symbol("b"), value: .integer(2))
        ])
        #expect(LingoValue.equalsBool(lhs: plist[0], rhs: .integer(1)))
        #expect(LingoValue.equalsBool(lhs: plist[1], rhs: .integer(2)))
    }

    @Test func iterateList() {
        let list: LingoValue = .list([.integer(1), .integer(2), .integer(3)])
        var sum = 0
        for item in list.asSequence() {
            if case .integer(let v) = item { sum += v }
        }
        #expect(sum == 6)
    }

    @Test func listCount() {
        let list: LingoValue = .list([.integer(1), .integer(2)])
        #expect(list.count.asInteger() == 2)
    }
}
