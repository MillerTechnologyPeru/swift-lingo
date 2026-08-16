import Testing

@testable import LingoRuntime

@Suite("Lingo List Commands")
struct ListCommandTests {

    private func integers(_ value: LingoValue) -> [Int]? {
        guard case .listType(let list) = value else { return nil }
        return list.elements.compactMap { $0.asInteger() }
    }

    private func keys(_ value: LingoValue) -> [String]? {
        guard case .propertyListType(let list) = value else { return nil }
        return list.elements.map { $0.key.asString() }
    }

    // MARK: Linear lists

    @Test func addAppendsToTheList() {
        let list = LingoValue.list([.integer(1), .integer(2)])
        list.listAdd(.integer(3))
        #expect(integers(list) == [1, 2, 3])
    }

    @Test func addAtInsertsAtAOneBasedPosition() {
        let list = LingoValue.list([.integer(1), .integer(3)])
        list.listAddAt(.integer(2), .integer(2))
        #expect(integers(list) == [1, 2, 3])
    }

    @Test func addAtPastTheEndPadsWithVoid() {
        let list = LingoValue.list([.integer(1)])
        list.listAddAt(.integer(3), .integer(9))
        guard case .listType(let raw) = list else { return }
        #expect(raw.elements.count == 3)
        if case .void = raw.elements[1] {} else { Issue.record("expected VOID padding") }
    }

    @Test func deleteAtRemovesByPosition() {
        let list = LingoValue.list([.integer(1), .integer(2), .integer(3)])
        list.listDeleteAt(.integer(2))
        #expect(integers(list) == [1, 3])
    }

    @Test func deleteAtIgnoresOutOfRangePositions() {
        let list = LingoValue.list([.integer(1)])
        list.listDeleteAt(.integer(0))
        list.listDeleteAt(.integer(5))
        #expect(integers(list) == [1])
    }

    @Test func deleteOneRemovesTheFirstMatch() {
        let list = LingoValue.list([.integer(7), .integer(8), .integer(7)])
        list.listDeleteOne(.integer(7))
        #expect(integers(list) == [8, 7])
    }

    /// `the actorList` holds script instances and they remove themselves by
    /// identity, so matching has to compare objects rather than contents.
    @Test func deleteOneMatchesObjectsByIdentity() {
        let environment = LingoEnvironment()
        let first = LingoObject(environment: environment)
        let second = LingoObject(environment: environment)
        let list = LingoValue.list([.object(first), .object(second)])

        list.listDeleteOne(.object(first))
        guard case .listType(let raw) = list else { return }
        #expect(raw.elements.count == 1)
        guard case .object(let remaining) = raw.elements[0] else { return }
        #expect(remaining === second)
    }

    @Test func getPosAnswersZeroWhenAbsent() {
        let list = LingoValue.list([.integer(4), .integer(5)])
        #expect(list.listGetPos(.integer(5)).asInteger() == 2)
        #expect(list.listGetPos(.integer(99)).asInteger() == 0)
    }

    @Test func getLastAnswersVoidWhenEmpty() {
        #expect(LingoValue.list([.integer(1), .integer(2)]).listGetLast().asInteger() == 2)
        if case .void = LingoValue.list([]).listGetLast() {} else {
            Issue.record("expected VOID from an empty list")
        }
    }

    @Test func sortOrdersLinearListsByValue() {
        let list = LingoValue.list([.integer(3), .integer(1), .integer(2)])
        list.listSort()
        #expect(integers(list) == [1, 2, 3])
    }

    @Test func duplicateCopiesSoMutationDoesNotLeak() {
        let original = LingoValue.list([.integer(1)])
        let copy = original.listDuplicate()
        copy.listAdd(.integer(2))
        #expect(integers(original) == [1])
        #expect(integers(copy) == [1, 2])
    }

    // MARK: Property lists

    @Test func addPropAppendsEvenWhenTheKeyRepeats() {
        let list = LingoValue.propertyList([(key: .symbol("a"), value: .integer(1))])
        list.listAddProp(.symbol("a"), .integer(2))
        #expect(keys(list) == ["a", "a"])
    }

    @Test func setAPropReplacesRatherThanAppending() {
        let list = LingoValue.propertyList([(key: .symbol("a"), value: .integer(1))])
        list.listSetAProp(.symbol("a"), .integer(2))
        #expect(keys(list) == ["a"])
        #expect(list.listGetAProp(.symbol("a")).asInteger() == 2)
    }

    @Test func setAPropAddsAMissingKey() {
        let list = LingoValue.propertyList([])
        list.listSetAProp(.symbol("b"), .integer(5))
        #expect(list.listGetAProp(.symbol("b")).asInteger() == 5)
    }

    @Test func getAPropAnswersVoidForAMissingKey() {
        let list = LingoValue.propertyList([(key: .symbol("a"), value: .integer(1))])
        if case .void = list.listGetAProp(.symbol("zzz")) {} else {
            Issue.record("expected VOID for a missing key")
        }
    }

    @Test func getPropAtAnswersTheKey() {
        let list = LingoValue.propertyList([
            (key: .symbol("a"), value: .integer(1)),
            (key: .symbol("b"), value: .integer(2)),
        ])
        #expect(list.listGetPropAt(.integer(2)).asString() == "b")
        if case .void = list.listGetPropAt(.integer(9)) {} else {
            Issue.record("expected VOID past the end")
        }
    }

    @Test func findPosAnswersVoidWhenAbsent() {
        let list = LingoValue.propertyList([(key: .symbol("a"), value: .integer(1))])
        #expect(list.listFindPos(.symbol("a")).asInteger() == 1)
        if case .void = list.listFindPos(.symbol("q")) {} else {
            Issue.record("expected VOID for a missing key")
        }
    }

    @Test func deletePropRemovesByKey() {
        let list = LingoValue.propertyList([
            (key: .symbol("a"), value: .integer(1)),
            (key: .symbol("b"), value: .integer(2)),
        ])
        list.listDeleteProp(.symbol("a"))
        #expect(keys(list) == ["b"])
    }

    /// On a property list `deleteOne` matches values, not keys.
    @Test func deleteOneOnAPropertyListMatchesValues() {
        let list = LingoValue.propertyList([
            (key: .symbol("a"), value: .integer(1)),
            (key: .symbol("b"), value: .integer(2)),
        ])
        list.listDeleteOne(.integer(2))
        #expect(keys(list) == ["a"])
    }

    @Test func nonListsIgnoreListCommands() {
        let notAList = LingoValue.integer(3)
        notAList.listAdd(.integer(1))
        #expect(notAList.asInteger() == 3)
        #expect(notAList.listGetPos(.integer(1)).asInteger() == 0)
    }
}

@Suite("Property List Dot Access")
struct PropertyListMemberTests {

    /// `glob.download_manager` and `glob.getaProp(#download_manager)` are the
    /// same lookup — dot syntax is how scripts normally read a property list.
    @Test func dotAccessReadsAKey() {
        let list = LingoValue.propertyList([(key: .symbol("player"), value: .integer(7))])
        #expect(list.player.asInteger() == 7)
    }

    @Test func dotAccessAnswersVoidForAMissingKey() {
        let list = LingoValue.propertyList([])
        if case .void = list.missing {} else { Issue.record("expected VOID") }
    }

    @Test func dotAssignmentSetsAKey() {
        let list = LingoValue.propertyList([])
        list.player = .integer(9)
        #expect(list.listGetAProp(.symbol("player")).asInteger() == 9)
    }

    @Test func dotAssignmentReplacesRatherThanDuplicating() {
        let list = LingoValue.propertyList([(key: .symbol("a"), value: .integer(1))])
        list.a = .integer(2)
        guard case .propertyListType(let raw) = list else { return }
        #expect(raw.elements.count == 1)
        #expect(list.a.asInteger() == 2)
    }

    /// `count` keeps its own meaning rather than being read as a key.
    @Test func countStaysAnIntrinsic() {
        let list = LingoValue.propertyList([
            (key: .symbol("a"), value: .integer(1)),
            (key: .symbol("b"), value: .integer(2)),
        ])
        #expect(list.count.asInteger() == 2)
    }

    @Test func linearListsIgnoreDotAccess() {
        let list = LingoValue.list([.integer(1)])
        if case .void = list.anything {} else { Issue.record("expected VOID from a linear list") }
    }
}
