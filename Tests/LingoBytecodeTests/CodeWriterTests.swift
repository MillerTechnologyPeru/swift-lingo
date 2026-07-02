import Testing

@testable import LingoBytecode

@Test func codeWriterIndentsOnlyAtLineStart() {
    let code = CodeWriter()
    code.write("if x then")
    code.endLine()
    code.indent()
    code.write("put ")
    code.write("1")
    code.write(" into y")
    code.endLine()
    code.unindent()
    code.write("end if")

    #expect(code.intoString() == "if x then\n  put 1 into y\nend if")
}

@Test func codeWriterUnindentClampsAtZero() {
    let code = CodeWriter()
    code.unindent()
    #expect(code.currentIndent == 0)
}
