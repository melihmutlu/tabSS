import Testing
@testable import TabssCore

struct SelectionTests {
    @Test func wrapsForwardAndBackward() {
        var selection = Selection(count: 3, index: 2)
        selection.next()
        #expect(selection.index == 0)
        selection.previous()
        #expect(selection.index == 2)
    }

    @Test func clampsInitialAndSelectedIndex() {
        #expect(Selection(count: 3, index: 9).index == 2)
        #expect(Selection(count: 3, index: -1).index == 0)
        var selection = Selection(count: 3, index: 0)
        selection.select(7)
        #expect(selection.index == 2)
    }

    @Test func emptySelectionIsStable() {
        var selection = Selection(count: 0, index: 5)
        selection.next()
        selection.previous()
        #expect(selection.index == 0)
        #expect(selection.isEmpty)
    }

    @Test func singleItemNeverMoves() {
        var selection = Selection(count: 1, index: 0)
        selection.next()
        #expect(selection.index == 0)
        selection.previous()
        #expect(selection.index == 0)
    }

    @Test func fullCycleReturnsToStart() {
        var selection = Selection(count: 4, index: 1)
        for _ in 0..<4 { selection.next() }
        #expect(selection.index == 1)
        for _ in 0..<4 { selection.previous() }
        #expect(selection.index == 1)
    }

    @Test func negativeCountIsTreatedAsEmpty() {
        let selection = Selection(count: -3, index: 2)
        #expect(selection.count == 0)
        #expect(selection.isEmpty)
        #expect(selection.index == 0)
    }

    @Test func selectClampsNegativeAndIgnoresEmpty() {
        var selection = Selection(count: 3, index: 2)
        selection.select(-5)
        #expect(selection.index == 0)
        var empty = Selection(count: 0, index: 0)
        empty.select(3)
        #expect(empty.index == 0)
    }

    @Test func containsOnlyIndicesInRange() {
        let selection = Selection(count: 3, index: 0)
        #expect([-1, 0, 1, 2, 3].map(selection.contains) == [false, true, true, true, false])
        #expect(!Selection(count: 0, index: 0).contains(0))
    }
}
