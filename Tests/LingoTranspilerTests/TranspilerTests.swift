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
}
