/// Lingo's list commands, the ones scripts call as methods on a list
/// (`myList.add(x)`, `props.getaProp(#key)`).
///
/// Lists are the workhorse data structure in Director — `the actorList` is
/// one, and any movie of size keeps its state in them — so a list that
/// can't be mutated leaves large parts of a movie silently doing nothing.
///
/// Positions are 1-based throughout, and an out-of-range position is not an
/// error: Director returns VOID (or leaves the list alone) rather than
/// trapping, and so does this.
extension LingoValue {
    /// Whether this value is a list of either kind.
    public var isList: Bool {
        switch self {
        case .listType, .propertyListType: return true
        default: return false
        }
    }

    /// The linear list this value holds, if it is one.
    private var linearList: LingoListClass? {
        if case .listType(let list) = self { return list }
        return nil
    }

    /// The property list this value holds, if it is one.
    private var propertyList: LingoPropertyListClass? {
        if case .propertyListType(let list) = self { return list }
        return nil
    }

    /// Converts a 1-based Lingo position to an index, or `nil` when it falls
    /// outside `count`.
    private static func index(_ position: LingoValue, count: Int) -> Int? {
        guard let position = position.asInteger(), position >= 1, position <= count else {
            return nil
        }
        return position - 1
    }

    // MARK: - Linear lists

    /// `add` — appends to a linear list.
    ///
    /// Director inserts in sort order instead when the list has been sorted;
    /// sortedness isn't tracked here, so this always appends, which is what
    /// `add` does for the unsorted lists scripts overwhelmingly build.
    public func listAdd(_ value: LingoValue) {
        linearList?.elements.append(value)
    }

    /// `append` — appends regardless of sort order.
    public func listAppend(_ value: LingoValue) {
        linearList?.elements.append(value)
    }

    /// `addAt` — inserts at a 1-based position, padding with VOID when the
    /// position is past the end, as Director does.
    public func listAddAt(_ position: LingoValue, _ value: LingoValue) {
        guard let list = linearList, let position = position.asInteger(), position >= 1 else {
            return
        }
        while list.elements.count < position - 1 {
            list.elements.append(.void)
        }
        list.elements.insert(value, at: min(position - 1, list.elements.count))
    }

    /// `deleteAt` — removes the entry at a 1-based position.
    public func listDeleteAt(_ position: LingoValue) {
        if let list = linearList, let index = Self.index(position, count: list.elements.count) {
            list.elements.remove(at: index)
        } else if let list = propertyList,
            let index = Self.index(position, count: list.elements.count)
        {
            list.elements.remove(at: index)
        }
    }

    /// `deleteOne` — removes the first entry equal to `value`. On a property
    /// list this matches against values, not keys, which is what makes
    /// `(the actorList).deleteOne(me)` work whichever kind of list it is.
    public func listDeleteOne(_ value: LingoValue) {
        if let list = linearList {
            if let index = list.elements.firstIndex(where: {
                LingoValue.equalsBool(lhs: $0, rhs: value)
            }) {
                list.elements.remove(at: index)
            }
        } else if let list = propertyList {
            if let index = list.elements.firstIndex(where: {
                LingoValue.equalsBool(lhs: $0.value, rhs: value)
            }) {
                list.elements.remove(at: index)
            }
        }
    }

    /// `getPos` — the 1-based position of `value`, or 0 when absent.
    public func listGetPos(_ value: LingoValue) -> LingoValue {
        if let list = linearList {
            let found = list.elements.firstIndex { LingoValue.equalsBool(lhs: $0, rhs: value) }
            return .integer(found.map { $0 + 1 } ?? 0)
        }
        if let list = propertyList {
            let found = list.elements.firstIndex {
                LingoValue.equalsBool(lhs: $0.value, rhs: value)
            }
            return .integer(found.map { $0 + 1 } ?? 0)
        }
        return .integer(0)
    }

    /// `getOne` — like `getPos` for a linear list; on a property list it
    /// answers with the key holding `value` rather than its position.
    public func listGetOne(_ value: LingoValue) -> LingoValue {
        if let list = propertyList {
            let found = list.elements.first { LingoValue.equalsBool(lhs: $0.value, rhs: value) }
            return found?.key ?? .integer(0)
        }
        return listGetPos(value)
    }

    /// `getLast` — the final entry, or VOID when the list is empty.
    public func listGetLast() -> LingoValue {
        if let list = linearList { return list.elements.last ?? .void }
        if let list = propertyList { return list.elements.last?.value ?? .void }
        return .void
    }

    /// `sort` — orders a linear list by value, a property list by key.
    /// Director leaves the list sorted from then on; see `listAdd`.
    public func listSort() {
        if let list = linearList {
            list.elements.sort { LingoValue.lessThanBool(lhs: $0, rhs: $1) }
        } else if let list = propertyList {
            list.elements.sort { LingoValue.lessThanBool(lhs: $0.key, rhs: $1.key) }
        }
    }

    /// `duplicate` — a shallow copy, so mutating the result leaves the
    /// original alone. Nested lists stay shared, matching Director.
    public func listDuplicate() -> LingoValue {
        if let list = linearList { return .list(list.elements) }
        if let list = propertyList { return .propertyList(list.elements) }
        return self
    }

    // MARK: - Property lists

    /// `addProp` — appends a key/value pair without replacing an existing
    /// entry for that key, which is how a property list ends up with
    /// duplicate keys in Director.
    public func listAddProp(_ key: LingoValue, _ value: LingoValue) {
        propertyList?.elements.append((key: key, value: value))
    }

    /// `setaProp` — replaces the value for `key`, adding the pair when the
    /// key isn't present yet.
    public func listSetAProp(_ key: LingoValue, _ value: LingoValue) {
        guard let list = propertyList else { return }
        if let index = list.elements.firstIndex(where: {
            LingoValue.equalsBool(lhs: $0.key, rhs: key)
        }) {
            list.elements[index].value = value
        } else {
            list.elements.append((key: key, value: value))
        }
    }

    /// `getaProp` — the value for `key`, or VOID when absent. (Lingo's
    /// `getProp` raises on a missing key where this one answers VOID; the
    /// forgiving spelling is the one scripts guard with `voidp`.)
    public func listGetAProp(_ key: LingoValue) -> LingoValue {
        guard let list = propertyList else { return .void }
        let found = list.elements.first { LingoValue.equalsBool(lhs: $0.key, rhs: key) }
        return found?.value ?? .void
    }

    /// `getPropAt` — the key at a 1-based position, or VOID.
    public func listGetPropAt(_ position: LingoValue) -> LingoValue {
        guard let list = propertyList,
            let index = Self.index(position, count: list.elements.count)
        else { return .void }
        return list.elements[index].key
    }

    /// `deleteProp` — removes the entry for `key`. On a linear list Lingo
    /// treats the argument as a position instead, so this defers to
    /// `deleteAt` there.
    public func listDeleteProp(_ key: LingoValue) {
        guard let list = propertyList else {
            listDeleteAt(key)
            return
        }
        if let index = list.elements.firstIndex(where: {
            LingoValue.equalsBool(lhs: $0.key, rhs: key)
        }) {
            list.elements.remove(at: index)
        }
    }

    /// `findPos` — the 1-based position of `key`, or VOID when absent.
    public func listFindPos(_ key: LingoValue) -> LingoValue {
        guard let list = propertyList else { return .void }
        let found = list.elements.firstIndex { LingoValue.equalsBool(lhs: $0.key, rhs: key) }
        return found.map { .integer($0 + 1) } ?? .void
    }
}
