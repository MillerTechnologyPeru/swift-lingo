// LingoValue+Chunks.swift
// LingoRuntime module - Embedded Swift compatible

/// Lingo's string chunk expressions (`char`/`word`/`item`/`line`).
///
/// Chunks resolve to a SLICE OF THE SOURCE STRING spanning the selected
/// chunks, so whatever separated them survives verbatim — RETURNs, tabs,
/// runs of spaces. Splitting into tokens and re-joining with a canonical
/// separator (the previous approach) collapsed every delimiter, so
/// `msg.word[2..msg.word.count]` came back as one line with its newlines
/// turned into spaces.
///
/// Range numbers follow Director's compiler conventions: positions are
/// 1-based; an end of `0` means "just the start chunk"; an end of `-1` (or
/// past the last chunk) means "through the last chunk"; and a start at or
/// below `-30000` is the compiler's sentinel for "the last chunk" (`delete
/// the last char of t` compiles to `delete char -30000 of t`).
extension LingoValue {
    private static func isDirectorWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\r" || character == "\n"
    }

    /// The source ranges of each chunk of `type` in `string`.
    ///
    /// Words are maximal runs of non-whitespace. Lines split on the string's
    /// own line break, sniffed per Director's tolerance for foreign text:
    /// `\r\n` when present, else `\n` when present, else `\r` — and the
    /// empty string has no lines. Items split on the delimiter, keeping
    /// empty items. Chars are individual characters.
    private static func chunkRanges(
        of string: String, type: String, itemDelimiter: Character = ","
    ) -> [Range<String.Index>] {
        switch type.asciiLowercased() {
        case "char":
            var ranges: [Range<String.Index>] = []
            var index = string.startIndex
            while index < string.endIndex {
                let next = string.index(after: index)
                ranges.append(index..<next)
                index = next
            }
            return ranges
        case "word":
            var ranges: [Range<String.Index>] = []
            var start: String.Index?
            var index = string.startIndex
            while index < string.endIndex {
                if isDirectorWhitespace(string[index]) {
                    if let wordStart = start {
                        ranges.append(wordStart..<index)
                        start = nil
                    }
                } else if start == nil {
                    start = index
                }
                index = string.index(after: index)
            }
            if let wordStart = start {
                ranges.append(wordStart..<string.endIndex)
            }
            return ranges
        case "line", "paragraph":
            guard !string.isEmpty else { return [] }
            let lineBreak: String
            if string.contains("\r\n") {
                lineBreak = "\r\n"
            } else if string.contains("\n") {
                lineBreak = "\n"
            } else {
                lineBreak = "\r"
            }
            return separatedRanges(of: string, separator: lineBreak)
        case "item":
            return separatedRanges(of: string, separator: String(itemDelimiter))
        default:
            return [string.startIndex..<string.endIndex]
        }
    }

    /// Ranges between occurrences of `separator`, keeping empty chunks.
    private static func separatedRanges(
        of string: String, separator: String
    ) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var chunkStart = string.startIndex
        var index = string.startIndex
        while index < string.endIndex {
            if string[index...].starts(with: separator) {
                ranges.append(chunkStart..<index)
                guard
                    let afterSeparator = string.index(
                        index, offsetBy: separator.count, limitedBy: string.endIndex)
                else { break }
                chunkStart = afterSeparator
                index = afterSeparator
            } else {
                index = string.index(after: index)
            }
        }
        ranges.append(chunkStart..<string.endIndex)
        return ranges
    }

    /// `string` with `lower..<upper` replaced — `replacingCharacters` without
    /// Foundation, which this module avoids for Embedded Swift.
    private static func replacing(
        _ string: String, _ lower: String.Index, _ upper: String.Index, with replacement: String
    ) -> String {
        String(string[string.startIndex..<lower]) + replacement
            + String(string[upper..<string.endIndex])
    }

    /// Normalizes a Director chunk range to 0-based chunk indices, or `nil`
    /// when it selects nothing.
    private static func hostChunkRange(start: Int, end: Int, count: Int) -> Range<Int>? {
        guard count > 0 else { return nil }
        if start <= -30000 {
            return (count - 1)..<count
        }
        let lower = Swift.max(0, start - 1)
        let upper: Int
        if end == 0 {
            upper = start <= 0 ? lower : lower + 1
        } else if end < 0 || end > count {
            upper = count
        } else {
            upper = end
        }
        let clampedLower = Swift.min(lower, count)
        let clampedUpper = Swift.min(upper, count)
        guard clampedLower < clampedUpper else { return nil }
        return clampedLower..<clampedUpper
    }

    /// The `itemDelimiter` parameters below are `the itemDelimiter` in
    /// effect for the call — a movie-wide setting scripts change freely
    /// (`the itemDelimiter = ";"`) to pick apart their own data formats.
    public func chunk(
        _ type: String, start: LingoValue, end: LingoValue?, itemDelimiter: Character = ","
    ) -> LingoValue {
        guard case .string(let string) = self, let startIndex = start.asInteger() else {
            return .void
        }
        let ranges = Self.chunkRanges(of: string, type: type, itemDelimiter: itemDelimiter)
        guard
            let selected = Self.hostChunkRange(
                start: startIndex, end: end?.asInteger() ?? 0, count: ranges.count)
        else { return .string("") }
        let lower = ranges[selected.lowerBound].lowerBound
        let upper = ranges[selected.upperBound - 1].upperBound
        return .string(String(string[lower..<upper]))
    }

    public func lastChunk(_ type: String, itemDelimiter: Character = ",") -> LingoValue {
        guard case .string(let string) = self else { return .void }
        guard let range = Self.chunkRanges(of: string, type: type, itemDelimiter: itemDelimiter).last
        else {
            return .string("")
        }
        return .string(String(string[range]))
    }

    public func chunkCount(_ type: String, itemDelimiter: Character = ",") -> LingoValue {
        guard case .string(let string) = self else { return .integer(0) }
        return .integer(Self.chunkRanges(of: string, type: type, itemDelimiter: itemDelimiter).count)
    }

    /// `put value into chunk` — replaces the selected span in the source,
    /// leaving everything around it untouched. A start past the last chunk
    /// appends, padded with the type's separator.
    public func settingChunk(
        _ type: String, start: LingoValue, end: LingoValue?, value: LingoValue,
        itemDelimiter: Character = ","
    ) -> LingoValue {
        let string = self.asString()
        let startIndex = start.asInteger() ?? 1
        let ranges = Self.chunkRanges(of: string, type: type, itemDelimiter: itemDelimiter)

        if let selected = Self.hostChunkRange(
            start: startIndex, end: end?.asInteger() ?? 0, count: ranges.count)
        {
            let lower = ranges[selected.lowerBound].lowerBound
            let upper = ranges[selected.upperBound - 1].upperBound
            return .string(Self.replacing(string, lower, upper, with: value.asString()))
        }

        guard startIndex > ranges.count else { return .string(string) }
        let separator: String
        switch type.asciiLowercased() {
        case "word": separator = " "
        case "item": separator = String(itemDelimiter)
        case "line", "paragraph": separator = "\r"
        default: separator = ""
        }
        let padding = String(
            repeating: separator, count: Swift.max(1, startIndex - Swift.max(ranges.count, 1)))
        return .string(string + padding + value.asString())
    }

    /// `delete chunk` — distinct from putting an empty string into it:
    /// deleting a word eats the whitespace run after it (or before it, for
    /// the last word), and deleting an item or line takes one adjoining
    /// separator with it, so the remaining chunks close ranks.
    public func deletingChunk(
        _ type: String, start: LingoValue, end: LingoValue?, itemDelimiter: Character = ","
    ) -> LingoValue {
        let string = self.asString()
        guard let startIndex = start.asInteger() else { return .string(string) }
        let ranges = Self.chunkRanges(of: string, type: type, itemDelimiter: itemDelimiter)
        guard
            let selected = Self.hostChunkRange(
                start: startIndex, end: end?.asInteger() ?? 0, count: ranges.count)
        else { return .string(string) }

        var lower = ranges[selected.lowerBound].lowerBound
        var upper = ranges[selected.upperBound - 1].upperBound

        switch type.asciiLowercased() {
        case "word":
            if upper < string.endIndex {
                while upper < string.endIndex, Self.isDirectorWhitespace(string[upper]) {
                    upper = string.index(after: upper)
                }
            } else {
                while lower > string.startIndex {
                    let previous = string.index(before: lower)
                    guard Self.isDirectorWhitespace(string[previous]) else { break }
                    lower = previous
                }
            }
        case "item", "line", "paragraph":
            // Take one separator so neighbors join up: the one after the
            // deleted span, or the one before it when the span is last.
            if selected.upperBound < ranges.count {
                upper = ranges[selected.upperBound].lowerBound
            } else if selected.lowerBound > 0 {
                lower = ranges[selected.lowerBound - 1].upperBound
            }
        default:
            break
        }
        return .string(Self.replacing(string, lower, upper, with: ""))
    }
}
