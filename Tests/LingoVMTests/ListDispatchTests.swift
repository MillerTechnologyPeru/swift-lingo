import LingoRuntime
import Testing

@testable import LingoVM

/// List commands reach the VM as ordinary method calls whose receiver is a
/// list rather than an object, so they need their own dispatch step —
/// without it `(the actorList).add(me)` silently does nothing.
@Suite("Lingo VM List Dispatch")
struct ListDispatchTests {

    @Test func addMutatesTheReceivingList() {
        let list = LingoValue.list([.integer(1)])
        let result = LingoVMExecutor.dispatchListCall(
            method: "add", receiver: list, args: [.integer(2)])
        #expect(result != nil)
        guard case .listType(let raw) = list else { return }
        #expect(raw.elements.compactMap { $0.asInteger() } == [1, 2])
    }

    @Test func methodNamesAreCaseInsensitive() {
        let list = LingoValue.propertyList([])
        _ = LingoVMExecutor.dispatchListCall(
            method: "setAProp", receiver: list, args: [.symbol("k"), .integer(7)])
        #expect(list.listGetAProp(.symbol("k")).asInteger() == 7)
    }

    @Test func queriesReturnTheirValue() {
        let list = LingoValue.list([.integer(4), .integer(5)])
        let position = LingoVMExecutor.dispatchListCall(
            method: "getPos", receiver: list, args: [.integer(5)])
        #expect(position?.asInteger() == 2)
    }

    @Test func missingArgumentsBecomeVoidRatherThanTrapping() {
        let list = LingoValue.list([.integer(1)])
        let result = LingoVMExecutor.dispatchListCall(method: "add", receiver: list, args: [])
        #expect(result != nil)
        guard case .listType(let raw) = list else { return }
        #expect(raw.elements.count == 2)
    }

    /// Anything that isn't a list command, or isn't aimed at a list, has to
    /// fall through so ordinary object dispatch still runs.
    @Test func unrelatedCallsFallThrough() {
        #expect(
            LingoVMExecutor.dispatchListCall(
                method: "somethingElse", receiver: .list([]), args: []) == nil)
        #expect(
            LingoVMExecutor.dispatchListCall(
                method: "add", receiver: .integer(3), args: [.integer(1)]) == nil)
    }
}
