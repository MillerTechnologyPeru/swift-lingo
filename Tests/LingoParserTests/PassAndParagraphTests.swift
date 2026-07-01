import Testing
@testable import LingoAST
@testable import LingoParser

@Suite
struct PassAndParagraphTests {
    private func parse(_ source: String) -> (Script, [Token]) {
        var lexer = Lexer(input: source)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let script = parser.parseScript()
        return (script, parser.skippedTokens)
    }

    @Test
    func parsesPassStatement() {
        let (script, skipped) = parse(
            """
            on keyDown me
                pass
            end
            """)
        #expect(skipped.isEmpty)
        guard case .handler(_, _, let body) = script.statements.first else {
            Issue.record("Expected handler")
            return
        }
        #expect(body == [.pass])
    }

    @Test
    func parsesParagraphChunk() {
        let (script, skipped) = parse(
            """
            on test me
                put paragraph 2 of myText into p
            end
            """)
        #expect(skipped.isEmpty)
        guard case .handler(_, _, let body) = script.statements.first,
            case .put(_, let value, _) = body.first
        else {
            Issue.record("Expected put statement")
            return
        }
        guard case .chunkExpression(let type, _, _, _, _) = value else {
            Issue.record("Expected chunk expression, got \(value)")
            return
        }
        #expect(type == .paragraph)
    }

    @Test
    func parsesParagraphCount() {
        let (script, skipped) = parse(
            """
            on test me
                put the number of paragraphs in myText into n
            end
            """)
        #expect(skipped.isEmpty)
        guard case .handler(_, _, let body) = script.statements.first,
            case .put(_, let value, _) = body.first,
            case .stringChunkCount(let type, _) = value
        else {
            Issue.record("Expected paragraph count expression")
            return
        }
        #expect(type == .paragraph)
    }

    @Test
    func roundTripsPassAndParagraph() async {
        let (script, _) = parse(
            """
            on test me
                pass
                put paragraph 1 of myText into p
            end
            """)
        let source = await script.toLingoSource()
        #expect(source.contains("pass"))
        #expect(source.contains("paragraph 1"))
    }
}
