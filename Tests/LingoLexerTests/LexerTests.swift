import XCTest
@testable import LingoLexer

final class LexerTests: XCTestCase {
    func testIdentifiersAndKeywords() {
        var lexer = Lexer(input: "on mouseUp me")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
            .identifier("on"),
            .identifier("mouseUp"),
            .identifier("me"),
            .eof
        ])
    }
    
    func testNumbers() {
        var lexer = Lexer(input: "123 45.67")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
            .integer(123),
            .number(45.67),
            .eof
        ])
    }
    
    func testSymbols() {
        var lexer = Lexer(input: "#PREGAME #state")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
            .symbol("PREGAME"),
            .symbol("state"),
            .eof
        ])
    }
    
    func testStrings() {
        var lexer = Lexer(input: "\"levels\" \"voice_ohyeah\"")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
            .string("levels"),
            .string("voice_ohyeah"),
            .eof
        ])
    }
    
    func testPunctuation() {
        var lexer = Lexer(input: "[](),.:")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
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
    
    func testOperators() {
        var lexer = Lexer(input: "+ - * / = < > <= >= <> & &&")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
            .plus, .minus, .multiply, .divide, .equals,
            .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual, .notEquals,
            .concat, .concatSpace, .eof
        ])
    }
    
    func testComments() {
        var lexer = Lexer(input: "on -- this is a comment\nme")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
            .identifier("on"),
            .newline,
            .identifier("me"),
            .eof
        ])
    }
    
    func testLineContinuation() {
        var lexer = Lexer(input: "on \\\n me")
        let tokens = lexer.tokenize()
        XCTAssertEqual(tokens, [
            .identifier("on"),
            .identifier("me"),
            .eof
        ])
    }
}
