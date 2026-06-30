import Testing
@testable import LingoAST
@testable import LingoParser

@Suite
struct ParserTests {
    @Test
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

        #expect(script.statements.count == 1)
        if case .handler(let name, let args, let body) = script.statements[0] {
            #expect(name == "new")
            #expect(args == ["me"])
            #expect(body.count == 2)

            if case .assignment(let target, let value) = body[0] {
                #expect(target == .identifier("gameState"))
                #expect(value == .symbol("PREGAME"))
            } else {
                Issue.record("Expected assignment statement")
            }

            if case .returnStatement(let expr) = body[1] {
                #expect(expr == .identifier("me"))
            } else {
                Issue.record("Expected return statement")
            }
        } else {
            Issue.record("Expected handler")
        }
    }

    @Test

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

        #expect(script.statements.count == 1)
        if case .handler(_, _, let body) = script.statements[0] {
            #expect(body.count == 1)
            if case .repeatWithCounter(let variable, let start, let end, let rBody, let up) = body[0] {
                #expect(variable == "n")
                #expect(start == .integer(1))
                #expect(end == .integer(5))
                #expect(rBody.count == 1)
                #expect(up)
            } else {
                Issue.record("Expected repeat statement")
            }
        } else {
            Issue.record("Expected handler")
        }
    }

    @Test

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

        #expect(script.statements.count == 1)
        if case .handler(_, _, let body) = script.statements[0] {
            #expect(body.count == 1)
            if case .ifStatement(let condition, let ifBody, let elseBody) = body[0] {
                if case .binaryOperation(let left, let op, let right) = condition {
                    #expect(left == .identifier("x"))
                    #expect(op == .lessThan)
                    #expect(right == .integer(10))
                } else {
                    Issue.record("Expected binary operation")
                }
                #expect(ifBody.count == 1)
                #expect(elseBody != nil)
                #expect(elseBody?.count == 1)
            } else {
                Issue.record("Expected if statement")
            }
        }
    }
}
