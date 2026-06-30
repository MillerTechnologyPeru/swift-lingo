import XCTest
@testable import LingoLexer
@testable import LingoAST
@testable import LingoParser

final class ParserTests: XCTestCase {
    func testParseHandler() {
        let input = """
        on new me
            gameState = #PREGAME
            return me
        end
        """
        
        var lexer = Lexer(input: input)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let script = parser.parseScript()
        
        XCTAssertEqual(script.statements.count, 1)
        if case .handler(let name, let args, let body) = script.statements[0] {
            XCTAssertEqual(name, "new")
            XCTAssertEqual(args, ["me"])
            XCTAssertEqual(body.count, 2)
            
            if case .assignment(let target, let value) = body[0] {
                XCTAssertEqual(target, .identifier("gameState"))
                XCTAssertEqual(value, .symbol("PREGAME"))
            } else {
                XCTFail("Expected assignment statement")
            }
            
            if case .returnStatement(let expr) = body[1] {
                XCTAssertEqual(expr, .identifier("me"))
            } else {
                XCTFail("Expected return statement")
            }
        } else {
            XCTFail("Expected handler")
        }
    }
    
    func testParseRepeat() {
         let input = """
         on myRepeat
             repeat with n = 1 to 5
                 n = n + 1
             end repeat
         end
         """
         var lexer = Lexer(input: input)
         let tokens = lexer.tokenize()
         let parser = Parser(tokens: tokens)
         let script = parser.parseScript()
         
         XCTAssertEqual(script.statements.count, 1)
         if case .handler(_, _, let body) = script.statements[0] {
             XCTAssertEqual(body.count, 1)
             if case .repeatWithCounter(let variable, let start, let end, let rBody) = body[0] {
                 XCTAssertEqual(variable, "n")
                 XCTAssertEqual(start, .integer(1))
                 XCTAssertEqual(end, .integer(5))
                 XCTAssertEqual(rBody.count, 1)
             } else {
                 XCTFail("Expected repeat statement")
             }
         } else {
             XCTFail("Expected handler")
         }
    }
    
    func testParseIf() {
        let input = """
        on myIf
            if x < 10 then
                x = x + 1
            else
                x = 0
            end if
        end
        """
        
        var lexer = Lexer(input: input)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let script = parser.parseScript()
        
        XCTAssertEqual(script.statements.count, 1)
        if case .handler(_, _, let body) = script.statements[0] {
             XCTAssertEqual(body.count, 1)
             if case .ifStatement(let condition, let ifBody, let elseBody) = body[0] {
                  if case .binaryOperation(let left, let op, let right) = condition {
                      XCTAssertEqual(left, .identifier("x"))
                      XCTAssertEqual(op, .lessThan)
                      XCTAssertEqual(right, .integer(10))
                  } else { XCTFail() }
                  XCTAssertEqual(ifBody.count, 1)
                  XCTAssertNotNil(elseBody)
                  XCTAssertEqual(elseBody?.count, 1)
             } else { XCTFail() }
        }
    }
}
