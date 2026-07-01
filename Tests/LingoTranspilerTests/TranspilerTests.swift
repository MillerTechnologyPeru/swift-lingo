import Testing
@testable import LingoAST
@testable import LingoParser
@testable import LingoTranspiler

@Suite
struct TranspilerTests {
    private func transpile(_ source: String) async -> String {
        var lexer = Lexer(input: source)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let script = parser.parseScript()
        let transpiler = LingoTranspiler(script: script, relativePath: "test.ls", originalPath: "test.ls")
        return await transpiler.transpile()
    }

    @Test
    func testTranspileHandler() async {
        let source = """
            on myHandler a, b
                put a + b into c
                return c
            end
            """
        let result = await transpile(source)
        #expect(result.contains("public func `myHandler`(_ `a`: LingoValue = LingoValue.void, _ `b`: LingoValue = LingoValue.void) -> LingoValue {"))
        #expect(result.contains("var `c`: LingoValue = .void"))
        #expect(result.contains("`c` = (`a` + `b`)"))
        #expect(result.contains("return `c`"))
    }

    @Test
    func testTranspileCaseRange() async {
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
        let result = await transpile(source)
        #expect(result.contains("case LingoRange(LingoValue.integer(1), LingoValue.integer(5)):"))
        #expect(result.contains("case LingoValue.integer(6), LingoRange(LingoValue.integer(7), LingoValue.integer(9)):"))
        #expect(result.contains("default:"))
        #expect(result.contains("return LingoValue.integer(0)"))
    }
    private func transpileExpr(_ source: String, locals: Set<String> = [], isMethod: Bool = false) async -> String {
        var lexer = Lexer(input: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let expr = parser.parseExpression() else {
            Issue.record("Failed to parse expression: \(source)")
            return ""
        }
        let transpiler = LingoTranspiler(script: Script(statements: []), relativePath: "test.ls", originalPath: "test.ls")
        return await transpiler.transpile(expression: expr, locals: locals, isMethod: isMethod)
    }

    @Test
    func testExpressions() async {
        // Primitives
        #expect(await transpileExpr("void") == "LingoValue.void")
        #expect(await transpileExpr("42") == "LingoValue.integer(42)")
        #expect(await transpileExpr("3.14") == "LingoValue.float(3.14)")
        #expect(await transpileExpr("\"hello\"") == "LingoValue.string(\"hello\")")
        #expect(await transpileExpr("#symbol") == "LingoValue.symbol(\"symbol\")")
        #expect(await transpileExpr("TRUE") == "LingoValue.integer(1)")
        #expect(await transpileExpr("FALSE") == "LingoValue.integer(0)")

        // Identifiers and Variables
        // Assuming no locals, identifiers default to LingoEnvironment.shared.getGlobal unless specialcased
        #expect(await transpileExpr("myVar") == "LingoEnvironment.shared.getGlobal(\"myVar\")")
        #expect(await transpileExpr("myVar", locals: ["myvar"]) == "`myvar`")

        #expect(await transpileExpr("the mouseH") == "LingoEnvironment.shared.getGlobal(\"mouseH\")")

        #expect(await transpileExpr("the width of sprite 1") == "LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(1)]).`width`")
        #expect(await transpileExpr("sprite(1).width") == "LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(1)]).`width`")

        #expect(await transpileExpr("obj.prop") == "LingoEnvironment.shared.getGlobal(\"obj\").`prop`")
        #expect(await transpileExpr("the prop of obj") == "LingoEnvironment.shared.getGlobal(\"obj\").`prop`")

        #expect(await transpileExpr("myList[1]") == "LingoEnvironment.shared.getGlobal(\"myList\")[LingoValue.integer(1)]")
        #expect(await transpileExpr("myList[1]", locals: ["mylist"]) == "`mylist`[LingoValue.integer(1)]")

        // Collections
        #expect(await transpileExpr("[]") == "LingoValue.list([])")
        #expect(await transpileExpr("[1, 2]") == "LingoValue.list([LingoValue.integer(1), LingoValue.integer(2)])")
        #expect(await transpileExpr("[:]") == "LingoValue.propertyList([])")
        #expect(await transpileExpr("[#a: 1]") == "LingoValue.propertyList([(key: LingoValue.symbol(\"a\"), value: LingoValue.integer(1))])")

        // Calls
        #expect(await transpileExpr("foo()") == "LingoEnvironment.shared.callGlobal(\"foo\", args: [])")
        #expect(await transpileExpr("foo(1, 2)") == "LingoEnvironment.shared.callGlobal(\"foo\", args: [LingoValue.integer(1), LingoValue.integer(2)])")
        #expect(await transpileExpr("obj.foo()") == "LingoEnvironment.shared.getGlobal(\"obj\").`foo`()")
        #expect(await transpileExpr("call(#foo, obj)") == "LingoEnvironment.shared.callGlobal(\"call\", args: [LingoValue.symbol(\"foo\"), LingoEnvironment.shared.getGlobal(\"obj\")])")

        // Operations
        #expect(await transpileExpr("1 + 2") == "(LingoValue.integer(1) + LingoValue.integer(2))")
        #expect(await transpileExpr("not TRUE") == "((LingoValue.integer(1)).asBool() ? LingoValue.integer(0) : LingoValue.integer(1))")
        #expect(await transpileExpr("-5") == "(-LingoValue.integer(5))")

        // Chunks
        #expect(await transpileExpr("word 1 of \"hello world\"") == "LingoValue.string(\"hello world\").chunk(\"word\", start: LingoValue.integer(1), end: nil)")
        #expect(await transpileExpr("char 1 to 3 of \"abc\"") == "LingoValue.string(\"abc\").chunk(\"char\", start: LingoValue.integer(1), end: LingoValue.integer(3))")
        #expect(await transpileExpr("the last word of \"hello\"") == "LingoValue.string(\"hello\").lastChunk(\"word\")")
        #expect(await transpileExpr("the number of words in \"hello\"") == "LingoValue.string(\"hello\").chunkCount(\"word\")")

        // Environment
        #expect(await transpileExpr("member(\"btn\")") == "LingoEnvironment.shared.callGlobal(\"member\", args: [LingoValue.string(\"btn\")])")
        #expect(await transpileExpr("sprite(1)") == "LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(1)])")
        #expect(
            await transpileExpr("sprite(1) intersects sprite(2)")
                == "LingoEnvironment.shared.callGlobal(\"intersects\", args: [LingoValue.integer(1), LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(2)])])")
        #expect(
            await transpileExpr("sprite(1) within sprite(2)")
                == "LingoEnvironment.shared.callGlobal(\"within\", args: [LingoValue.integer(1), LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(2)])])")

        #expect(await transpileExpr("the name of menu 1") == "LingoEnvironment.shared.callGlobal(\"menu\", args: [LingoValue.integer(1)]).`name`")
        #expect(
            await transpileExpr("the name of menu item 1 of menu 2")
                == "LingoEnvironment.shared.callGlobal(\"menu\", args: [LingoEnvironment.shared.getGlobal(\"menu\").chunk(\"item\", start: LingoValue.integer(1), end: nil)]).`name`")
        #expect(await transpileExpr("the name of sound 1") == "LingoEnvironment.shared.callGlobal(\"sound\", args: [LingoValue.integer(1)]).`name`")
    }
}
