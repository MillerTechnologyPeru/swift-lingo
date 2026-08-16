// LingoEnvironment+Builtins.swift
// LingoRuntime module - Embedded Swift compatible

extension LingoEnvironment {
    /// Registers Lingo's language-level functions — the ones that belong to
    /// the language rather than to a host. Each is implemented as a plain
    /// Swift function in `LingoBuiltins` (callable directly); this only maps
    /// the Lingo call convention (a name and an argument array) onto those
    /// functions.
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
        register1("count", LingoBuiltins.count)

        // MARK: List commands in their function spelling
        //
        // Lingo accepts both `myList.getAt(1)` and `getAt(myList, 1)`, and
        // compiled code uses whichever the author wrote. `repeat with x in
        // list` in particular lowers to the function spelling, so these are
        // not just a convenience — without them the loop variable is VOID
        // on every iteration. The direct Swift functions here are
        // `LingoValue`'s own list methods (`listAdd`, `listGetAProp`, ...).
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

        register1("voidp", LingoBuiltins.voidP)
        registerGlobalFunction("ilk") { args in
            LingoBuiltins.ilk(args.first ?? .void, args.count > 1 ? args[1] : nil)
        }
        register1("listp", LingoBuiltins.listP)
        register1("stringp", LingoBuiltins.stringP)
        register1("symbolp", LingoBuiltins.symbolP)
        register1("objectp", LingoBuiltins.objectP)
        register1("integerp", LingoBuiltins.integerP)
        register1("floatp", LingoBuiltins.floatP)

        // MARK: Coercions

        register1("string", LingoBuiltins.string)
        register1("symbol", LingoBuiltins.symbol)
        register1("integer", LingoBuiltins.integer)
        register1("float", LingoBuiltins.float)
        register1("value", LingoBuiltins.value)

        // MARK: Strings

        register1("length", LingoBuiltins.length)
        register2("offset", LingoBuiltins.offset)
        registerGlobalFunction("chars") { args in
            LingoBuiltins.chars(
                args.first ?? .void,
                args.count > 1 ? args[1] : .void,
                args.count > 2 ? args[2] : .void)
        }
        register1("numtochar", LingoBuiltins.numToChar)
        register1("chartonum", LingoBuiltins.charToNum)

        // MARK: Arithmetic

        register1("abs", LingoBuiltins.abs)
        registerGlobalFunction("max") { LingoBuiltins.max($0) }
        registerGlobalFunction("min") { LingoBuiltins.min($0) }
    }

    /// Wires a one-argument builtin, passing VOID when the call site
    /// supplied nothing.
    private func register1(_ name: String, _ function: @escaping (LingoValue) -> LingoValue) {
        registerGlobalFunction(name) { args in
            function(args.first ?? .void)
        }
    }

    /// Wires a two-argument builtin the same way.
    private func register2(
        _ name: String, _ function: @escaping (LingoValue, LingoValue) -> LingoValue
    ) {
        registerGlobalFunction(name) { args in
            function(args.first ?? .void, args.count > 1 ? args[1] : .void)
        }
    }

    /// Wires a list command in its function spelling, where the list is the
    /// first argument. A call aimed at anything else answers VOID rather
    /// than doing something surprising.
    private func registerListFunction(
        _ name: String, _ body: @escaping (LingoValue, [LingoValue]) -> LingoValue
    ) {
        registerGlobalFunction(name) { args in
            guard let list = args.first, list.isList else { return .void }
            return body(list, Array(args.dropFirst()))
        }
    }
}
