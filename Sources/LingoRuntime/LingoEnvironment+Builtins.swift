// LingoEnvironment+Builtins.swift
// LingoRuntime module - Embedded Swift compatible

extension LingoEnvironment {
    /// Registers Lingo's language-level functions — the ones that belong to
    /// the language rather than to a host (`count`, `voidp`, the type
    /// predicates, the coercions).
    ///
    /// These matter more than their simplicity suggests. Compiled Lingo
    /// calls them as ordinary named functions, and an unregistered name
    /// evaluates to VOID rather than failing, so a missing builtin doesn't
    /// look like an error — it looks like the script deciding not to do
    /// anything. `repeat with x in someList` compiles to a `count(someList)`
    /// call and a `1 <= count` test, so without `count` every such loop
    /// silently runs zero times.
    ///
    /// A host may re-register any of these to give it host-specific
    /// behavior; the later registration wins.
    public func registerStandardBuiltins() {
        registerGlobalFunction("count") { args in
            guard let first = args.first else { return .integer(0) }
            return first.count
        }

        // MARK: List commands in their function spelling
        //
        // Lingo accepts both `myList.getAt(1)` and `getAt(myList, 1)`, and
        // compiled code uses whichever the author wrote. `repeat with x in
        // list` in particular lowers to the function spelling, so these are
        // not just a convenience — without them the loop variable is VOID
        // on every iteration.
        registerListFunction("getat") { list, args in list[args.first ?? .void] }
        registerListFunction("setat") { list, args in
            list.setElement(index: args.first ?? .void, value: (args.count > 1 ? args[1] : .void))
            return .void
        }
        registerListFunction("add") { list, args in
            list.listAdd(args.first ?? .void)
            return .void
        }
        registerListFunction("append") { list, args in
            list.listAppend(args.first ?? .void)
            return .void
        }
        registerListFunction("addat") { list, args in
            list.listAddAt(args.first ?? .void, (args.count > 1 ? args[1] : .void))
            return .void
        }
        registerListFunction("deleteat") { list, args in
            list.listDeleteAt(args.first ?? .void)
            return .void
        }
        registerListFunction("deleteone") { list, args in
            list.listDeleteOne(args.first ?? .void)
            return .void
        }
        registerListFunction("deleteprop") { list, args in
            list.listDeleteProp(args.first ?? .void)
            return .void
        }
        registerListFunction("addprop") { list, args in
            list.listAddProp(args.first ?? .void, (args.count > 1 ? args[1] : .void))
            return .void
        }
        registerListFunction("setaprop") { list, args in
            list.listSetAProp(args.first ?? .void, (args.count > 1 ? args[1] : .void))
            return .void
        }
        registerListFunction("sort") { list, _ in
            list.listSort()
            return .void
        }
        registerListFunction("getpos") { list, args in list.listGetPos(args.first ?? .void) }
        registerListFunction("getone") { list, args in list.listGetOne(args.first ?? .void) }
        registerListFunction("getlast") { list, _ in list.listGetLast() }
        registerListFunction("getaprop") { list, args in list.listGetAProp(args.first ?? .void) }
        registerListFunction("getpropat") { list, args in list.listGetPropAt(args.first ?? .void) }
        registerListFunction("findpos") { list, args in list.listFindPos(args.first ?? .void) }
        registerListFunction("duplicate") { list, _ in list.listDuplicate() }

        // MARK: Type inspection

        registerGlobalFunction("voidp") { args in
            guard let first = args.first else { return .integer(1) }
            if case .void = first { return .integer(1) }
            return .integer(0)
        }
        registerGlobalFunction("ilk") { args in
            guard let first = args.first else { return .symbol("void") }
            let kind = LingoEnvironment.ilkName(of: first)
            // `ilk(x, #type)` asks whether x is that type rather than which.
            if args.count > 1, case .symbol(let wanted) = args[1] {
                var matches = kind.caseInsensitiveEquals(wanted)
                // A property list is also a list, as Lingo reports it.
                if !matches, wanted.caseInsensitiveEquals("list") {
                    matches = first.isList
                }
                return .integer(matches ? 1 : 0)
            }
            return .symbol(kind)
        }
        registerPredicate("listp") { $0.isList }
        registerPredicate("stringp") { if case .string = $0 { return true } else { return false } }
        registerPredicate("symbolp") { if case .symbol = $0 { return true } else { return false } }
        registerPredicate("objectp") { if case .object = $0 { return true } else { return false } }
        registerPredicate("integerp") {
            if case .integer = $0 { return true } else { return false }
        }
        registerPredicate("floatp") { if case .float = $0 { return true } else { return false } }

        // MARK: Coercions

        registerGlobalFunction("string") { args in
            .string(args.first?.asString() ?? "")
        }
        registerGlobalFunction("symbol") { args in
            .symbol(args.first?.asString() ?? "")
        }
        registerGlobalFunction("integer") { args in
            guard let value = args.first?.asInteger() else { return .void }
            return .integer(value)
        }
        registerGlobalFunction("float") { args in
            guard let first = args.first else { return .void }
            switch first {
            case .float(let value): return .float(value)
            case .integer(let value): return .float(Double(value))
            default:
                guard let value = first.asInteger() else { return .void }
                return .float(Double(value))
            }
        }
        registerGlobalFunction("value") { args in
            guard let first = args.first else { return .void }
            guard case .string(let text) = first else { return first }
            let trimmed = String(
                text.drop(while: { $0 == " " || $0 == "\t" })
                    .reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
            if let integer = Int(trimmed) { return .integer(integer) }
            if let double = Double(trimmed) { return .float(double) }
            return .void
        }

        // MARK: Strings
        //
        // `offset` in particular guards `repeat while` loops all over real
        // movies (`repeat while offset(numToChar(10), t) > 0`), so a VOID
        // stand-in changes loop behavior rather than failing visibly.

        registerGlobalFunction("length") { args in
            guard case .string(let text)? = args.first else { return .integer(0) }
            return .integer(text.count)
        }
        registerGlobalFunction("offset") { args in
            // offset(needle, haystack) — 1-based, 0 when absent,
            // case-insensitive like the rest of Lingo's string handling.
            guard args.count >= 2 else { return .integer(0) }
            let needle = args[0].asString().asciiLowercased()
            let haystack = args[1].asString().asciiLowercased()
            guard !needle.isEmpty, !haystack.isEmpty else { return .integer(0) }
            let needleChars = Array(needle)
            let haystackChars = Array(haystack)
            guard needleChars.count <= haystackChars.count else { return .integer(0) }
            for start in 0...(haystackChars.count - needleChars.count) {
                var matches = true
                for i in 0..<needleChars.count where haystackChars[start + i] != needleChars[i] {
                    matches = false
                    break
                }
                if matches { return .integer(start + 1) }
            }
            return .integer(0)
        }
        registerGlobalFunction("chars") { args in
            // chars(string, first, last) — inclusive 1-based slice.
            guard args.count >= 3, case .string(let text) = args[0],
                let first = args[1].asInteger(), let last = args[2].asInteger()
            else { return .string("") }
            let characters = Array(text)
            let lower = Swift.max(1, first)
            let upper = Swift.min(characters.count, last)
            guard lower <= upper else { return .string("") }
            return .string(String(characters[(lower - 1)..<upper]))
        }
        registerGlobalFunction("numToChar") { args in
            guard let code = args.first?.asInteger(), let scalar = Unicode.Scalar(UInt32(bitPattern: Int32(truncatingIfNeeded: code)) & 0xFF)
            else { return .string("") }
            return .string(String(Character(scalar)))
        }
        registerGlobalFunction("charToNum") { args in
            guard case .string(let text)? = args.first, let first = text.unicodeScalars.first
            else { return .integer(0) }
            return .integer(Int(first.value))
        }

        // MARK: Arithmetic

        registerGlobalFunction("abs") { args in
            guard let first = args.first else { return .void }
            switch first {
            case .integer(let value): return .integer(value < 0 ? -value : value)
            case .float(let value): return .float(value < 0 ? -value : value)
            default: return .void
            }
        }
        registerGlobalFunction("max") { args in
            LingoEnvironment.extreme(of: args, keepingLeft: false)
        }
        registerGlobalFunction("min") { args in
            LingoEnvironment.extreme(of: args, keepingLeft: true)
        }
    }

    /// Registers a list command in its function spelling, where the list is
    /// the first argument. A call aimed at anything else answers VOID
    /// rather than doing something surprising.
    private func registerListFunction(
        _ name: String, _ body: @escaping (LingoValue, [LingoValue]) -> LingoValue
    ) {
        registerGlobalFunction(name) { args in
            guard let list = args.first, list.isList else { return .void }
            return body(list, Array(args.dropFirst()))
        }
    }

    private func registerPredicate(_ name: String, _ test: @escaping (LingoValue) -> Bool) {
        registerGlobalFunction(name) { args in
            guard let first = args.first else { return .integer(0) }
            return .integer(test(first) ? 1 : 0)
        }
    }

    private static func ilkName(of value: LingoValue) -> String {
        switch value {
        case .void: return "void"
        case .integer: return "integer"
        case .float: return "float"
        case .string: return "string"
        case .symbol: return "symbol"
        case .listType: return "list"
        case .propertyListType: return "propList"
        case .object, .boundMethod, .globalFunction: return "object"
        }
    }

    /// `max`/`min` accept either a list or a run of arguments.
    private static func extreme(of args: [LingoValue], keepingLeft: Bool) -> LingoValue {
        var values = args
        if args.count == 1, case .listType(let list) = args[0] {
            values = list.elements
        }
        guard var best = values.first else { return .void }
        for value in values.dropFirst() {
            let takeNew =
                keepingLeft
                ? LingoValue.lessThanBool(lhs: value, rhs: best)
                : LingoValue.lessThanBool(lhs: best, rhs: value)
            if takeNew { best = value }
        }
        return best
    }
}
