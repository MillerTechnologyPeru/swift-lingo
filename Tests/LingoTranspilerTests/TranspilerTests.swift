import Testing
@testable import LingoAST
@testable import LingoParser
@testable import LingoTranspiler

@Suite
struct TranspilerTests {
    private func transpile(_ source: String) -> String {
        var lexer = Lexer(input: source)
        let tokens = lexer.tokenize()
        let parser = Parser(tokens: tokens)
        let script = parser.parseScript()
        let transpiler = LingoTranspiler(script: script, relativePath: "test.ls", originalPath: "test.ls")
        return transpiler.transpile()
    }

    @Test
    func testTranspileHandler() {
        let source = """
            on myHandler a, b
                put a + b into c
                return c
            end
            """
        let result = transpile(source)
        #expect(result.contains("public func `myHandler`(_ `a`: LingoValue = LingoValue.void, _ `b`: LingoValue = LingoValue.void) -> LingoValue {"))
        #expect(result.contains("var `c`: LingoValue = .void"))
        #expect(result.contains("`c` = (`a` + `b`)"))
        #expect(result.contains("return `c`"))
    }

    @Test
    func testTranspileCaseRange() {
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
        let result = transpile(source)
        #expect(result.contains("case LingoRange(LingoValue.integer(1), LingoValue.integer(5)):"))
        #expect(result.contains("case LingoValue.integer(6), LingoRange(LingoValue.integer(7), LingoValue.integer(9)):"))
        #expect(result.contains("default:"))
        #expect(result.contains("return LingoValue.integer(0)"))
    }
    private func transpileExpr(_ source: String, locals: Set<String> = [], isMethod: Bool = false) -> String {
        var lexer = Lexer(input: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let expr = parser.parseExpression() else {
            Issue.record("Failed to parse expression: \(source)")
            return ""
        }
        let transpiler = LingoTranspiler(script: Script(statements: []), relativePath: "test.ls", originalPath: "test.ls")
        return transpiler.transpile(expression: expr, locals: locals, isMethod: isMethod)
    }

    @Test
    func testExpressions() {
        // Primitives
        #expect(transpileExpr("void") == "LingoValue.void")
        #expect(transpileExpr("42") == "LingoValue.integer(42)")
        #expect(transpileExpr("3.14") == "LingoValue.float(3.14)")
        #expect(transpileExpr("\"hello\"") == "LingoValue.string(\"hello\")")
        #expect(transpileExpr("#symbol") == "LingoValue.symbol(\"symbol\")")
        #expect(transpileExpr("TRUE") == "LingoValue.integer(1)")
        #expect(transpileExpr("FALSE") == "LingoValue.integer(0)")

        // Identifiers and Variables
        // Assuming no locals, identifiers default to LingoEnvironment.shared.getGlobal unless specialcased
        #expect(transpileExpr("myVar") == "LingoEnvironment.shared.getGlobal(\"myVar\")")
        #expect(transpileExpr("myVar", locals: ["myvar"]) == "`myvar`")

        #expect(transpileExpr("the mouseH") == "LingoEnvironment.shared.getGlobal(\"mouseH\")")

        #expect(transpileExpr("the width of sprite 1") == "LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(1)]).`width`")
        #expect(transpileExpr("sprite(1).width") == "LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(1)]).`width`")

        #expect(transpileExpr("obj.prop") == "LingoEnvironment.shared.getGlobal(\"obj\").`prop`")
        #expect(transpileExpr("the prop of obj") == "LingoEnvironment.shared.getGlobal(\"obj\").`prop`")

        #expect(transpileExpr("myList[1]") == "LingoEnvironment.shared.getGlobal(\"myList\")[LingoValue.integer(1)]")
        #expect(transpileExpr("myList[1]", locals: ["mylist"]) == "`mylist`[LingoValue.integer(1)]")

        // Collections
        #expect(transpileExpr("[]") == "LingoValue.list([])")
        #expect(transpileExpr("[1, 2]") == "LingoValue.list([LingoValue.integer(1), LingoValue.integer(2)])")
        #expect(transpileExpr("[:]") == "LingoValue.propertyList([])")
        #expect(transpileExpr("[#a: 1]") == "LingoValue.propertyList([(key: LingoValue.symbol(\"a\"), value: LingoValue.integer(1))])")

        // Calls
        #expect(transpileExpr("foo()") == "LingoEnvironment.shared.callGlobal(\"foo\", args: [])")
        #expect(transpileExpr("foo(1, 2)") == "LingoEnvironment.shared.callGlobal(\"foo\", args: [LingoValue.integer(1), LingoValue.integer(2)])")
        #expect(transpileExpr("obj.foo()") == "LingoEnvironment.shared.getGlobal(\"obj\").`foo`()")
        #expect(transpileExpr("call(#foo, obj)") == "LingoEnvironment.shared.callGlobal(\"call\", args: [LingoValue.symbol(\"foo\"), LingoEnvironment.shared.getGlobal(\"obj\")])")

        // Operations
        #expect(transpileExpr("1 + 2") == "(LingoValue.integer(1) + LingoValue.integer(2))")
        #expect(transpileExpr("not TRUE") == "((LingoValue.integer(1)).asBool() ? LingoValue.integer(0) : LingoValue.integer(1))")
        #expect(transpileExpr("-5") == "(-LingoValue.integer(5))")

        // Chunks
        #expect(transpileExpr("word 1 of \"hello world\"") == "LingoValue.string(\"hello world\").chunk(\"word\", start: LingoValue.integer(1), end: nil)")
        #expect(transpileExpr("char 1 to 3 of \"abc\"") == "LingoValue.string(\"abc\").chunk(\"char\", start: LingoValue.integer(1), end: LingoValue.integer(3))")
        #expect(transpileExpr("the last word of \"hello\"") == "LingoValue.string(\"hello\").lastChunk(\"word\")")
        #expect(transpileExpr("the number of words in \"hello\"") == "LingoValue.string(\"hello\").chunkCount(\"word\")")

        // Environment
        #expect(transpileExpr("member(\"btn\")") == "LingoEnvironment.shared.callGlobal(\"member\", args: [LingoValue.string(\"btn\")])")
        #expect(transpileExpr("sprite(1)") == "LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(1)])")
        #expect(
            transpileExpr("sprite(1) intersects sprite(2)")
                == "LingoEnvironment.shared.callGlobal(\"intersects\", args: [LingoValue.integer(1), LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(2)])])")
        #expect(
            transpileExpr("sprite(1) within sprite(2)")
                == "LingoEnvironment.shared.callGlobal(\"within\", args: [LingoValue.integer(1), LingoEnvironment.shared.callGlobal(\"sprite\", args: [LingoValue.integer(2)])])")

        #expect(transpileExpr("the name of menu 1") == "LingoEnvironment.shared.callGlobal(\"menu\", args: [LingoValue.integer(1)]).`name`")
        #expect(
            transpileExpr("the name of menu item 1 of menu 2")
                == "LingoEnvironment.shared.callGlobal(\"menu\", args: [LingoEnvironment.shared.getGlobal(\"menu\").chunk(\"item\", start: LingoValue.integer(1), end: nil)]).`name`")
        #expect(transpileExpr("the name of sound 1") == "LingoEnvironment.shared.callGlobal(\"sound\", args: [LingoValue.integer(1)]).`name`")
    }
}
