// LingoObject+Builtins.swift
// LingoRuntime module - Embedded Swift compatible

/// The standard builtins as `LingoObject` instance methods.
///
/// Transpiled Lingo emits a bare function call as `self.<name>(...)` — a
/// handler call resolved at compile time. Handlers defined in the same
/// script become the class's own methods; the language's builtin functions
/// resolve here instead, delegating to the same `LingoBuiltins`
/// implementations the name-dispatched path uses, so transpiled and
/// interpreted code can't drift apart.
extension LingoObject {
    public func count(_ value: LingoValue) -> LingoValue { LingoBuiltins.count(value) }

    public func voidP(_ value: LingoValue) -> LingoValue { LingoBuiltins.voidP(value) }
    public func ilk(_ value: LingoValue) -> LingoValue { LingoBuiltins.ilk(value) }
    public func ilk(_ value: LingoValue, _ type: LingoValue) -> LingoValue {
        LingoBuiltins.ilk(value, type)
    }
    public func listP(_ value: LingoValue) -> LingoValue { LingoBuiltins.listP(value) }
    public func stringP(_ value: LingoValue) -> LingoValue { LingoBuiltins.stringP(value) }
    public func symbolP(_ value: LingoValue) -> LingoValue { LingoBuiltins.symbolP(value) }
    public func objectP(_ value: LingoValue) -> LingoValue { LingoBuiltins.objectP(value) }
    public func integerP(_ value: LingoValue) -> LingoValue { LingoBuiltins.integerP(value) }
    public func floatP(_ value: LingoValue) -> LingoValue { LingoBuiltins.floatP(value) }

    public func string(_ value: LingoValue) -> LingoValue { LingoBuiltins.string(value) }
    public func symbol(_ value: LingoValue) -> LingoValue { LingoBuiltins.symbol(value) }
    public func integer(_ value: LingoValue) -> LingoValue { LingoBuiltins.integer(value) }
    public func float(_ value: LingoValue) -> LingoValue { LingoBuiltins.float(value) }
    public func value(_ input: LingoValue) -> LingoValue { LingoBuiltins.value(input) }

    public func length(_ value: LingoValue) -> LingoValue { LingoBuiltins.length(value) }
    public func offset(_ needle: LingoValue, _ haystack: LingoValue) -> LingoValue {
        LingoBuiltins.offset(needle, haystack)
    }
    public func chars(_ text: LingoValue, _ first: LingoValue, _ last: LingoValue) -> LingoValue {
        LingoBuiltins.chars(text, first, last)
    }
    public func point(_ h: LingoValue, _ v: LingoValue) -> LingoValue { LingoBuiltins.point(h, v) }
    public func rect(
        _ left: LingoValue, _ top: LingoValue, _ right: LingoValue, _ bottom: LingoValue
    ) -> LingoValue { LingoBuiltins.rect(left, top, right, bottom) }
    public func rect(_ topLeft: LingoValue, _ bottomRight: LingoValue) -> LingoValue {
        LingoBuiltins.rect(topLeft, bottomRight)
    }
    public func numToChar(_ code: LingoValue) -> LingoValue { LingoBuiltins.numToChar(code) }
    public func charToNum(_ text: LingoValue) -> LingoValue { LingoBuiltins.charToNum(text) }

    public func abs(_ value: LingoValue) -> LingoValue { LingoBuiltins.abs(value) }
    public func max(_ values: LingoValue...) -> LingoValue { LingoBuiltins.max(values) }
    public func min(_ values: LingoValue...) -> LingoValue { LingoBuiltins.min(values) }
}
