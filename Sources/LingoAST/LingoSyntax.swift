/// The two textual dialects Director's Lingo scripting dictionary documents as
/// equivalent: the older sentence-like form and the object-oriented form
/// introduced to mirror JavaScript.
///
/// - `verbose`: `set the crop of member "x" to TRUE`, `word 2 of paragraph 1 of member("x")`
/// - `dot`: `member("x").crop = TRUE`, `member("x").paragraph[1].word[2]`
public enum LingoSyntax: Sendable, CaseIterable, Equatable {
    case verbose
    case dot
}
