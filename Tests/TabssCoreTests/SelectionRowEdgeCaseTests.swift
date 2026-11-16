import CoreGraphics
import Testing
@testable import TabssCore

struct SelectionRowEdgeCaseTests {
    private func walk(_ start: Selection, _ step: (inout Selection) -> Void, times: Int) -> [Int] {
        var selection = start
        return (0..<times).map { _ in
            step(&selection)
            return selection.index
        }
    }

    @Test func oneColumnDownAndUpCycleThroughEveryItem() {
        let start = Selection(count: 3, index: 0, columns: 1)
        #expect(walk(start, { $0.down() }, times: 4) == [1, 2, 0, 1])
        #expect(walk(start, { $0.up() }, times: 4) == [2, 1, 0, 2])
    }

    @Test func countEqualToColumnsIsASingleRow() {
        for index in 0..<4 {
            var selection = Selection(count: 4, index: index, columns: 4)
            selection.down()
            #expect(selection.index == index)
            selection.up()
            #expect(selection.index == index)
        }
    }

    // 3 columns, 4 items:  0 1 2 / 3
    @Test func countOneMoreThanColumns() {
        #expect(walk(Selection(count: 4, index: 0, columns: 3), { $0.down() }, times: 2) == [3, 0])
        #expect(walk(Selection(count: 4, index: 1, columns: 3), { $0.down() }, times: 1) == [1])  // nothing below
        #expect(walk(Selection(count: 4, index: 2, columns: 3), { $0.down() }, times: 1) == [2])
        #expect(walk(Selection(count: 4, index: 0, columns: 3), { $0.up() }, times: 2) == [3, 0])
        #expect(walk(Selection(count: 4, index: 1, columns: 3), { $0.up() }, times: 2) == [3, 0])  // short last row → last item
        #expect(walk(Selection(count: 4, index: 2, columns: 3), { $0.up() }, times: 1) == [3])
    }

    @Test func columnsBeyondCountIsASingleRow() {
        for index in 0..<3 {
            var selection = Selection(count: 3, index: index, columns: 10)
            selection.down()
            #expect(selection.index == index)
            selection.up()
            #expect(selection.index == index)
        }
    }

    @Test func nonPositiveColumnsBehaveAsOneColumn() {
        #expect(Selection(count: 3, index: 0, columns: 0).columns == 1)
        #expect(Selection(count: 3, index: 0, columns: -2).columns == 1)
        #expect(walk(Selection(count: 3, index: 0, columns: 0), { $0.down() }, times: 3) == [1, 2, 0])
    }

    @Test func singleItemIgnoresRows() {
        var selection = Selection(count: 1, index: 0, columns: 3)
        selection.up()
        selection.down()
        #expect(selection.index == 0)
    }

    @Test func fullLastRowUpWrapsToSameColumn() {
        // 3 columns, 6 items:  0 1 2 / 3 4 5
        #expect(walk(Selection(count: 6, index: 2, columns: 3), { $0.up() }, times: 2) == [5, 2])
        #expect(walk(Selection(count: 6, index: 2, columns: 3), { $0.down() }, times: 2) == [5, 2])
    }

    /// Up and Down must move to the tile drawn directly above or below, including into a short last row.
    @Test func verticalMovesFollowTheDrawnColumns() {
        let metrics = TileLayout.Metrics()
        let width = 3 * 240 + 2 * metrics.tileSpacing + 2 * metrics.panelPadding
        let layout = TileLayout(itemCount: 7, maxPanelSize: CGSize(width: width, height: 2000), metrics: metrics)
        #expect(layout.columns == 3)
        // 0 1 2 / 3 4 5 / 6
        for start in 0..<7 {
            var selection = Selection(count: 7, index: start, columns: layout.columns)
            selection.down()
            #expect(layout.tileFrames[selection.index].minX == layout.tileFrames[start].minX, "down from \(start)")
        }
    }
}

struct SwitcherStateMachineRowTests {
    private var machine = SwitcherStateMachine()

    // 3 columns, 7 items:  0 1 2 / 3 4 5 / 6
    @Test mutating func reverseOpenThenUpAndDown() {
        _ = machine.handle(.open(reverse: true, itemCount: 7, firstItemIsFocused: true, columns: 3))
        #expect(machine.selectedIndex == 6)
        #expect(machine.handle(.command(.up)) == [])  // armed: tracked silently
        #expect(machine.selectedIndex == 3)
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [.show(selectedIndex: 3)])
        #expect(machine.handle(.command(.down)) == [.select(index: 6)])
        #expect(machine.handle(.command(.down)) == [.select(index: 0)])
        #expect(machine.handle(.command(.up)) == [.select(index: 6)])
        #expect(machine.handle(.command(.commit)) == [.hide, .activate(index: 6)])
    }

    @Test mutating func withoutColumnsUpAndDownAreNoOps() {
        _ = machine.handle(.open(reverse: false, itemCount: 5, firstItemIsFocused: true))
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(machine.handle(.command(.down)) == [])
        #expect(machine.handle(.command(.up)) == [])
        #expect(machine.selectedIndex == 1)
    }

    @Test mutating func columnsDoNotLeakIntoTheNextSession() {
        _ = machine.handle(.open(reverse: false, itemCount: 6, firstItemIsFocused: true, columns: 2))
        _ = machine.handle(.command(.cancel))
        _ = machine.handle(.open(reverse: false, itemCount: 6, firstItemIsFocused: true))
        _ = machine.handle(.command(.down))
        #expect(machine.selectedIndex == 1)
    }

    @Test mutating func upAndDownWhileIdleDoNothing() {
        #expect(machine.handle(.command(.up)) == [])
        #expect(machine.handle(.command(.down)) == [])
        #expect(!machine.isActive)
    }
}
