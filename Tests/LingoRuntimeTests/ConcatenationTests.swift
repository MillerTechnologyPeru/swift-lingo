import Testing
@testable import LingoRuntime

@Suite("Lingo Concatenation Operators")
struct ConcatenationTests {

    private func string(_ value: LingoValue) -> String? {
        if case .string(let s) = value { return s }
        return nil
    }

    // MARK: & (concat, no separator)

    @Test func concatStrings() {
        let result = LingoValue.string("abra").concat(.string("cadabra"))
        #expect(string(result) == "abracadabra")
    }

    @Test func concatCoercesIntegers() {
        // Lingo `5 & 3` is "53", not arithmetic 8.
        let result = LingoValue.integer(5).concat(.integer(3))
        #expect(string(result) == "53")
    }

    @Test func concatMixesStringAndNumber() {
        let result = LingoValue.string("$").concat(.integer(9))
        #expect(string(result) == "$9")
    }

    // MARK: && (concat with space)

    @Test func concatSpaceInsertsSingleSpace() {
        let result = LingoValue.string("abra").concatSpace(.string("cadabra"))
        #expect(string(result) == "abra cadabra")
    }

    @Test func concatSpaceCoercesNumbers() {
        let result = LingoValue.string("Today is").concatSpace(.integer(7))
        #expect(string(result) == "Today is 7")
    }

    // MARK: asString coercion

    @Test func asStringForSymbol() {
        #expect(LingoValue.symbol("PREGAME").asString() == "PREGAME")
    }

    @Test func asStringForVoidIsEmpty() {
        #expect(LingoValue.void.asString() == "")
    }
}
