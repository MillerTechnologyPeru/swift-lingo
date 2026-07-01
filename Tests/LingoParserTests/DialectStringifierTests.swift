import Testing
@testable import LingoAST
@testable import LingoParser

/// Covers the verbose/dot dialect duality documented in Director's Lingo
/// scripting dictionary ("Scripting in dot syntax format"): every
/// dialect-convertible AST node remembers which spelling it was parsed from
/// (`LingoSyntax`), `toLingoSource()` with no argument reproduces that
/// original spelling exactly, and an explicit `syntax:` argument normalizes
/// a whole subtree to one dialect.
@Suite
struct DialectStringifierTests {
    private func parse(_ source: String) -> Script {
        var lexer = Lexer(input: source)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        return parser.parseScript()
    }

    /// Parses a single handler-body line and returns its statement.
    private func statement(from line: String) -> Statement? {
        let script = parse("on test me\n  \(line)\nend")
        guard case .handler(_, _, let body) = script.statements.first else { return nil }
        return body.first
    }

    private func expression(from line: String) -> Expression? {
        guard case .expressionStatement(let expr) = statement(from: line) else { return nil }
        return expr
    }

    // MARK: - Dot-syntax chunk access parses to `.chunkExpression`, not property+index

    @Test
    func dotSyntaxCharChunkParsesAsChunkExpression() {
        // Real usage: Internal/parent_database manager.ls:147 `charToNum(s.char[n])`
        guard case .chunkExpression(let type, let first, let last, let string, let syntax) = expression(from: "s.char[n]") else {
            Issue.record("Expected chunkExpression, got \(String(describing: expression(from: "s.char[n]")))")
            return
        }
        #expect(type == .char)
        #expect(first == .identifier("n"))
        #expect(last == nil)
        #expect(string == .identifier("s"))
        #expect(syntax == .dot)
    }

    @Test
    func dotSyntaxItemChunkParsesAsChunkExpression() {
        // Real usage: Internal/parent_database manager.ls:124 `pairs.add(s.item[p])`
        guard case .chunkExpression(let type, _, _, let string, let syntax) = expression(from: "s.item[p]") else {
            Issue.record("Expected chunkExpression")
            return
        }
        #expect(type == .item)
        #expect(string == .identifier("s"))
        #expect(syntax == .dot)
    }

    @Test
    func dotSyntaxRangeChunkParsesAsChunkExpression() {
        // Real usage: Internal/behavior_Display Text.ls:192 `parentString.char[1..position - 1]`
        guard case .chunkExpression(let type, let first, let last, _, let syntax) = expression(from: "parentString.char[1..position - 1]") else {
            Issue.record("Expected chunkExpression")
            return
        }
        #expect(type == .char)
        #expect(first == .integer(1))
        #expect(last == .binaryOperation(left: .identifier("position"), operator: .subtract, right: .integer(1)))
        #expect(syntax == .dot)
    }

    @Test
    func dotSyntaxChunkNestedInsideItsOwnCountIndex() {
        // The trickiest real fixture: Internal/behavior_config manager.ls:11
        // `L.char[L.char.count]` — the outer `.char[...]` must become a
        // chunkExpression (bracket follows), while the inner `L.char.count`
        // (no bracket directly after `.char`) stays a plain property chain,
        // since dot-form chunk *counting* isn't part of this fix.
        guard case .chunkExpression(let type, let first, let last, let string, let syntax) = expression(from: "L.char[L.char.count]") else {
            Issue.record("Expected chunkExpression")
            return
        }
        #expect(type == .char)
        #expect(string == .identifier("L"))
        #expect(last == nil)
        #expect(syntax == .dot)
        #expect(first == .propertyAccess(target: .propertyAccess(target: .identifier("L"), property: "char", syntax: .dot), property: "count", syntax: .dot))
    }

    @Test
    func dotSyntaxChunkFollowedByFurtherPropertyAccess() {
        // Real usage: catalog/parent_catalog manager.ls:128
        // `member(cattext).line[i].Hyperlink = hl`
        guard case .assignment(let target, let value, let assignSyntax) = statement(from: "member(cattext).line[i].Hyperlink = hl") else {
            Issue.record("Expected assignment")
            return
        }
        #expect(assignSyntax == .dot)
        #expect(value == .identifier("hl"))
        guard case .propertyAccess(let chunk, let prop, let propSyntax) = target else {
            Issue.record("Expected propertyAccess wrapping a chunkExpression, got \(target)")
            return
        }
        #expect(prop == "Hyperlink")
        #expect(propSyntax == .dot)
        guard case .chunkExpression(let type, let first, _, let string, let chunkSyntax) = chunk else {
            Issue.record("Expected chunkExpression under the propertyAccess")
            return
        }
        #expect(type == .line)
        #expect(first == .identifier("i"))
        #expect(chunkSyntax == .dot)
        #expect(string == .member(type: "member", id: .identifier("cattext"), castId: nil))
    }

    // MARK: - Verbose keyword chunk access still parses as `.chunkExpression(syntax: .verbose)`

    @Test
    func verboseNestedChunkParsesWithVerboseSyntax() {
        guard case .chunkExpression(let outerType, let outerFirst, _, let outerString, let outerSyntax) = expression(from: "word 2 of paragraph 1 of member(\"News Items\")") else {
            Issue.record("Expected chunkExpression")
            return
        }
        #expect(outerType == .word)
        #expect(outerFirst == .integer(2))
        #expect(outerSyntax == .verbose)
        guard case .chunkExpression(let innerType, let innerFirst, _, _, let innerSyntax) = outerString else {
            Issue.record("Expected nested chunkExpression")
            return
        }
        #expect(innerType == .paragraph)
        #expect(innerFirst == .integer(1))
        #expect(innerSyntax == .verbose)
    }

    // MARK: - `toLingoSource()` with no argument reproduces the original dialect exactly

    @Test
    func defaultRenderingReproducesEachStatementsOriginalDialect() async {
        let script = parse(
            """
            on test me
              set the crop of member("x") to TRUE
              member("y").crop = FALSE
            end
            """)
        let source = await script.toLingoSource()
        #expect(source.contains("set the crop of member(\"x\") to TRUE"))
        #expect(source.contains("member(\"y\").crop = FALSE"))
    }

    @Test
    func defaultRenderingReproducesDotChunkAccessVerbatim() async {
        guard case .expressionStatement = statement(from: "s.char[n]") else {
            Issue.record("Expected expression statement")
            return
        }
        let script = parse("on test me\n  s.char[n]\nend")
        let source = await script.toLingoSource()
        #expect(source.contains("s.char[n]"))
    }

    // MARK: - Forcing a dialect normalizes the whole subtree, including nested chunks

    @Test
    func forcingDotNormalizesVerboseNestedChunk() async throws {
        let script = parse(
            """
            on test me
              word 2 of paragraph 1 of member("News Items")
            end
            """)
        let dotSource = await script.toLingoSource(syntax: .dot)
        #expect(dotSource.contains(#"member("News Items").paragraph[1].word[2]"#))

        // Re-parsing the normalized text should itself round-trip when re-forced to dot.
        let reparsed = parse(dotSource)
        let reparsedDotSource = await reparsed.toLingoSource(syntax: .dot)
        #expect(reparsedDotSource == dotSource)
    }

    @Test
    func forcingVerboseNormalizesDotChunkAccess() async {
        let script = parse("on test me\n  member(\"News Items\").paragraph[1].word[2]\nend")
        let verboseSource = await script.toLingoSource(syntax: .verbose)
        #expect(verboseSource.contains(#"word 2 of paragraph 1 of member("News Items")"#))
    }

    @Test
    func forcingDotNormalizesVerboseAssignment() async {
        let script = parse("on test me\n  set the crop of member(\"x\") to TRUE\nend")
        let dotSource = await script.toLingoSource(syntax: .dot)
        #expect(dotSource.contains(#"member("x").crop = TRUE"#))
    }

    @Test
    func forcingVerboseNormalizesDotAssignment() async {
        let script = parse("on test me\n  member(\"x\").crop = TRUE\nend")
        let verboseSource = await script.toLingoSource(syntax: .verbose)
        #expect(verboseSource.contains(#"set the crop of member("x") to TRUE"#))
    }
}
