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

struct SelectionRowTests {
    private func walk(_ start: Selection, _ step: (inout Selection) -> Void, times: Int) -> [Int] {
        var selection = start
        return (0..<times).map { _ in
            step(&selection)
            return selection.index
        }
    }

    // 3 columns, 7 items, last row centered:  0 1 2 / 3 4 5 / . 6 .
    @Test func downAndUpGoToTheNearestDrawnTileAndStopAtTheEdges() {
        #expect(walk(Selection(count: 7, index: 1, columns: 3), { $0.down() }, times: 3) == [4, 6, 6])
        #expect(walk(Selection(count: 7, index: 6, columns: 3), { $0.up() }, times: 3) == [4, 1, 1])
        #expect(walk(Selection(count: 7, index: 3, columns: 3), { $0.down() }, times: 1) == [6])
        #expect(walk(Selection(count: 7, index: 5, columns: 3), { $0.down() }, times: 1) == [6])
    }

    // 5 columns, 8 items:  0 1 2 3 4 / . 5 6 7 .
    @Test func aShortRowUnderAWideRowMapsByPosition() {
        let below = (0..<5).map { start -> Int in
            var selection = Selection(count: 8, index: start, columns: 5)
            selection.down()
            return selection.index
        }
        #expect(below == [5, 5, 6, 7, 7])
        let above = (5..<8).map { start -> Int in
            var selection = Selection(count: 8, index: start, columns: 5)
            selection.up()
            return selection.index
        }
        #expect(above == [1, 2, 3])
    }

    @Test func aSingleRowHasNowhereToGo() {
        #expect(walk(Selection(count: 4, index: 2), { $0.down() }, times: 1) == [2])
        #expect(walk(Selection(count: 4, index: 2), { $0.up() }, times: 1) == [2])
    }

    @Test func emptySelectionIgnoresRows() {
        var selection = Selection(count: 0, index: 0, columns: 3)
        selection.up()
        selection.down()
        #expect(selection.index == 0)
    }
}
