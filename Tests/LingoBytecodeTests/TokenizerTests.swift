import Testing

@testable import LingoBytecode

@Test func tokenizeSimple() {
    let spans = tokenizeLine("put x into y")
    #expect(spans.count == 7)  // put, space, x, space, into, space, y
    #expect(spans[0].tokenType == .keyword)
    #expect(spans[2].tokenType == .identifier)
    #expect(spans[4].tokenType == .keyword)
    #expect(spans[6].tokenType == .identifier)
}

@Test func tokenizeString() {
    let spans = tokenizeLine(#"put "hello" into x"#)
    let stringSpan = spans.first { $0.tokenType == .string }
    #expect(stringSpan != nil)
    #expect(stringSpan?.text == #""hello""#)
}

@Test func tokenizeSymbol() {
    let spans = tokenizeLine("#mySymbol")
    #expect(spans[0].tokenType == .symbol)
    #expect(spans[0].text == "#mySymbol")
}

@Test func tokenizeNumber() {
    let spans = tokenizeLine("123 45.67 -89")
    let numbers = spans.filter { $0.tokenType == .number }
    #expect(numbers.count == 3)
}

@Test func tokenizeComment() {
    let spans = tokenizeLine("x = 1 -- this is a comment")
    let commentSpan = spans.first { $0.tokenType == .comment }
    #expect(commentSpan != nil)
    #expect(commentSpan?.text.hasPrefix("--") == true)
}
