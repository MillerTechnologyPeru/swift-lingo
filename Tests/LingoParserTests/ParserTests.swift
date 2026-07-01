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

    @Test func testParseCase() {
        let source = """
            on eval x
                case x of
                    1 to 5:
                        return 10
                    6, 7 to 9:
                        return 20
                    otherwise:
                        return 0
                end case
            end
            """
        var lexer = Lexer(input: source)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let script = parser.parseScript()

        if case .handler(_, _, let body) = script.statements[0] {
            if case .caseStatement(let cond, let cases, let otherwise) = body[0] {
                if case .identifier(let c) = cond { #expect(c == "x") } else { Issue.record("Fail") }

                #expect(cases.count == 2)

                // 1 to 5
                if case .range(let start, let end) = cases[0].values[0] {
                    if case .integer(let s) = start { #expect(s == 1) } else { Issue.record("Fail") }
                    if case .integer(let e) = end { #expect(e == 5) } else { Issue.record("Fail") }
                } else {
                    Issue.record("Expected range")
                }

                // 6, 7 to 9
                if case .integer(let v1) = cases[1].values[0] { #expect(v1 == 6) } else { Issue.record("Fail") }
                if case .range(let start, let end) = cases[1].values[1] {
                    if case .integer(let s) = start { #expect(s == 7) } else { Issue.record("Fail") }
                    if case .integer(let e) = end { #expect(e == 9) } else { Issue.record("Fail") }
                } else {
                    Issue.record("Expected range")
                }

                #expect(otherwise?.count == 1)
            } else {
                Issue.record("Expected case statement")
            }
        } else {
            Issue.record("Expected handler")
        }
    }
}
