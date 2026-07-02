/// Renders decompiled Lingo into indented source text, one `write`/`writeln`
/// call at a time. The two-space indent for the current `indentLevel` is
/// inserted lazily — only right before the first piece of text written on a
/// fresh line — so a statement built up from several `write` calls (e.g. an
/// expression's sub-nodes) doesn't get re-indented partway through.
final class CodeWriter {
    private var output = ""
    private var indentLevel: UInt32 = 0
    private var atLineStart = true

    init() {}

    func indent() {
        indentLevel += 1
    }

    func unindent() {
        if indentLevel > 0 {
            indentLevel -= 1
        }
    }

    func write(_ text: String) {
        if atLineStart, !text.isEmpty {
            output += String(repeating: "  ", count: Int(indentLevel))
            atLineStart = false
        }
        output += text
    }

    func writeln(_ text: String) {
        write(text)
        endLine()
    }

    func endLine() {
        output += "\n"
        atLineStart = true
    }

    func intoString() -> String {
        output
    }

    var currentIndent: UInt32 {
        indentLevel
    }
}
