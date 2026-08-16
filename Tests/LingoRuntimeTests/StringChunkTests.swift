import Testing

@testable import LingoRuntime

/// Director string-chunk semantics, cross-checked against dirplayer-rs's
/// passing reference tests (vm-rust `string_chunk` suite) so the two
/// implementations agree on the behaviors real movies depend on.
@Suite("Lingo String Chunks")
struct StringChunkTests {

    private func words(_ text: String, _ start: Int, _ end: Int) -> String {
        LingoValue.string(text).chunk("word", start: .integer(start), end: .integer(end)).asString()
    }

    private func deleteWord(_ text: String, _ start: Int) -> String {
        LingoValue.string(text).deletingChunk("word", start: .integer(start), end: .integer(0))
            .asString()
    }

    // MARK: Words are source slices

    /// `msg.word[2..msg.word.count]` — the returns between words must
    /// survive; joining tokens with " " turns a message body into one line.
    @Test func wordRangePreservesOriginalDelimiters() {
        #expect(words("cmd body\rline two\rline three", 2, -1) == "body\rline two\rline three")
        #expect(words("a\r\nb\tc", 1, 3) == "a\r\nb\tc")
    }

    @Test func wordRangeExcludesSurroundingWhitespace() {
        #expect(words("  a   b  ", 1, 2) == "a   b")
        #expect(words("  a   b  ", 2, 0) == "b")
    }

    @Test func wordSlicingIsCharacterAware() {
        #expect(words("héllo\rwörld", 1, 2) == "héllo\rwörld")
        #expect(words("héllo\rwörld", 2, 0) == "wörld")
    }

    @Test func outOfRangeWordsAreEmpty() {
        #expect(words("a b", 5, 9) == "")
        #expect(words("   ", 1, 0) == "")
        #expect(words("", 1, 0) == "")
    }

    // MARK: Deleting words

    /// ` text "name"` → delete word 1 must keep the leading space so a
    /// following `delete char 1` removes the space, not the opening quote.
    @Test func deleteWordPreservesLeadingWhitespace() {
        #expect(deleteWord(" text \"name\"", 1) == " \"name\"")
    }

    @Test func deleteWordEatsTheRightWhitespaceRun() {
        // A word takes the whitespace after it...
        #expect(deleteWord("a b c", 1) == "b c")
        #expect(deleteWord("a b c", 2) == "a c")
        // ...except the last word, which takes the whitespace before it.
        #expect(deleteWord("a b c", 3) == "a b")
        // Interior runs: only the deleted gap goes.
        #expect(deleteWord("a   b   c", 2) == "a   c")
    }

    // MARK: Director's range conventions

    /// `delete the last char of t` compiles to `delete char -30000 of t` —
    /// the junkbot sample uses exactly this to strip a trailing comma.
    @Test func minus30000SelectsTheLastChunk() {
        let record = LingoValue.string("37 4,")
        #expect(record.chunk("char", start: .integer(-30000), end: .integer(0)).asString() == ",")
        #expect(
            record.deletingChunk("char", start: .integer(-30000), end: .integer(0)).asString()
                == "37 4")
    }

    @Test func endZeroMeansJustTheStartChunk() {
        #expect(words("alpha beta gamma", 2, 0) == "beta")
    }

    @Test func endBeyondTheLastChunkClampsToIt() {
        #expect(words("alpha beta", 1, 99) == "alpha beta")
    }

    // MARK: Lines

    /// Lines split on the string's own break — junkbot's field text uses
    /// `\r`, converted files use `\n` or `\r\n`.
    @Test func linesSplitOnTheStringsOwnBreak() {
        let mac = LingoValue.string("one\rtwo\rthree")
        #expect(mac.chunk("line", start: .integer(2), end: .integer(0)).asString() == "two")
        #expect(mac.chunkCount("line").asInteger() == 3)

        let unix = LingoValue.string("one\ntwo")
        #expect(unix.chunk("line", start: .integer(2), end: .integer(0)).asString() == "two")

        let windows = LingoValue.string("one\r\ntwo")
        #expect(windows.chunkCount("line").asInteger() == 2)
        #expect(windows.chunk("line", start: .integer(1), end: .integer(0)).asString() == "one")
    }

    @Test func lineRangeIsASourceSlice() {
        let text = LingoValue.string("a\rb\rc")
        #expect(text.chunk("line", start: .integer(1), end: .integer(2)).asString() == "a\rb")
    }

    @Test func theEmptyStringHasNoLines() {
        #expect(LingoValue.string("").chunkCount("line").asInteger() == 0)
    }

    // MARK: Items and deletion joining

    @Test func itemsKeepEmptyEntries() {
        let csv = LingoValue.string("a,,c")
        #expect(csv.chunkCount("item").asInteger() == 3)
        #expect(csv.chunk("item", start: .integer(2), end: .integer(0)).asString() == "")
    }

    @Test func deletingAnItemTakesOneSeparator() {
        let csv = LingoValue.string("a,b,c")
        #expect(
            csv.deletingChunk("item", start: .integer(2), end: .integer(0)).asString() == "a,c")
        #expect(
            csv.deletingChunk("item", start: .integer(3), end: .integer(0)).asString() == "a,b")
        #expect(
            csv.deletingChunk("item", start: .integer(1), end: .integer(0)).asString() == "b,c")
    }

    @Test func deletingALineTakesItsBreak() {
        let text = LingoValue.string("one\rtwo\rthree")
        #expect(
            text.deletingChunk("line", start: .integer(2), end: .integer(0)).asString()
                == "one\rthree")
    }

    // MARK: Putting into chunks

    @Test func settingAChunkOnlyTouchesItsSpan() {
        let text = LingoValue.string("a\rb\rc")
        #expect(
            text.settingChunk("line", start: .integer(2), end: .integer(0), value: .string("B"))
                .asString() == "a\rB\rc")
        let sentence = LingoValue.string("one  two")
        #expect(
            sentence.settingChunk("word", start: .integer(2), end: .integer(0), value: .string("2"))
                .asString() == "one  2")
    }
}
