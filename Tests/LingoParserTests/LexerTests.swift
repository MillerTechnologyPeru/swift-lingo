import Testing
@testable import LingoParser

@Suite
struct LexerTests {
    @Test
    func testIdentifiersAndKeywords() {
        var lexer = Lexer(input: "on mouseUp me")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .identifier("on"),
            .identifier("mouseUp"),
            .identifier("me"),
            .eof
        ])
    }
    
    @Test
    
    func testNumbers() {
        var lexer = Lexer(input: "123 45.67")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .integer(123),
            .number(45.67),
            .eof
        ])
    }
    
    @Test
    
    func testSymbols() {
        var lexer = Lexer(input: "#PREGAME #state")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .symbol("PREGAME"),
            .symbol("state"),
            .eof
        ])
    }
    
    @Test
    
    func testStrings() {
        var lexer = Lexer(input: "\"levels\" \"voice_ohyeah\"")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .string("levels"),
            .string("voice_ohyeah"),
            .eof
        ])
    }
    
    @Test
    
    func testPunctuation() {
        var lexer = Lexer(input: "[](),.:")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .leftBracket,
            .rightBracket,
            .leftParen,
            .rightParen,
            .comma,
            .dot,
            .colon,
            .eof
        ])
    }
    
    @Test
    
    func testOperators() {
        var lexer = Lexer(input: "+ - * / = < > <= >= <> & &&")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .plus, .minus, .multiply, .divide, .equals,
            .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual, .notEquals,
            .concat, .concatSpace, .eof
        ])
    }
    
    @Test
    
    func testComments() {
        var lexer = Lexer(input: "on -- this is a comment\nme")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .identifier("on"),
            .newline,
            .identifier("me"),
            .eof
        ])
    }
    
    @Test
    
    func testLineContinuation() {
        var lexer = Lexer(input: "on \\\n me")
        let tokens = lexer.tokenize()
        #expect(tokens == [
            .identifier("on"),
            .identifier("me"),
            .eof
        ])
    }
}
