import CoreGraphics
import Testing
@testable import TabssCore

struct GridPositionTests {
    @Test func fullRowsAreNotShiftedAndShortRowsAreCentered() {
        let grid = GridPosition(count: 7, columns: 3)
        #expect(grid.rows == 3)
        #expect((0..<6).map(grid.horizontalPosition) == [0, 1, 2, 0, 1, 2])
        #expect(grid.horizontalPosition(of: 6) == 1)
        #expect(GridPosition(count: 8, columns: 5).horizontalPosition(of: 5) == 1)
        #expect(GridPosition(count: 6, columns: 4).horizontalPosition(of: 4) == 1)
    }

    @Test func nearestStopsPastTheEdges() {
        let grid = GridPosition(count: 7, columns: 3)
        #expect(grid.nearest(to: 1, rowDelta: -1) == nil)
        #expect(grid.nearest(to: 6, rowDelta: 1) == nil)
    }

    // 4 columns, 7 items:  0 1 2 3 / ½ 4 5 6 ½  — tile 1 sits exactly between 4 and 5.
    @Test func tiesGoToTheLeftTile() {
        #expect(GridPosition(count: 7, columns: 4).nearest(to: 1, rowDelta: 1) == 4)
        #expect(GridPosition(count: 7, columns: 4).nearest(to: 2, rowDelta: 1) == 5)
    }

    @Test func nonPositiveColumnsBehaveAsOneColumn() {
        #expect(GridPosition(count: 3, columns: 0).columns == 1)
        #expect(Selection(count: 3, index: 0, columns: -2).columns == 1)
    }

    /// The arrow keys and the drawing share the same positions: every vertical move lands on the drawn tile
    /// closest to where it started.
    @Test(arguments: [(7, 3), (8, 5), (6, 4), (13, 5)])
    func verticalMovesFollowTheDrawing(count: Int, columns: Int) {
        let metrics = TileLayout.Metrics()
        let width = CGFloat(columns) * 240 + CGFloat(columns - 1) * metrics.tileSpacing + 2 * metrics.panelPadding
        let layout = TileLayout(itemCount: count, maxPanelSize: CGSize(width: width, height: 5000), metrics: metrics)
        #expect(layout.columns == columns)
        let grid = GridPosition(count: count, columns: columns)
        for start in 0..<count {
            for delta in [-1, 1] {
                guard let target = grid.nearest(to: start, rowDelta: delta) else { continue }
                let distance = abs(layout.tileFrames[target].midX - layout.tileFrames[start].midX)
                let best = grid.indices(inRow: grid.row(of: target))
                    .map { abs(layout.tileFrames[$0].midX - layout.tileFrames[start].midX) }
                    .min()!
                #expect(distance <= best + 1, "from \(start) by \(delta)")
            }
        }
    }
}

struct SwitcherStateMachineRowTests {
    private var machine = SwitcherStateMachine()

    // 3 columns, 7 items:  0 1 2 / 3 4 5 / . 6 .
    @Test mutating func reverseOpenThenUpAndDown() {
        _ = machine.handle(.open(reverse: true, itemCount: 7, firstItemIsFocused: true, columns: 3))
        #expect(machine.selectedIndex == 6)
        #expect(machine.handle(.command(.up)) == [])  // armed: tracked silently
        #expect(machine.selectedIndex == 4)
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [.show(selectedIndex: 4)])
        #expect(machine.handle(.command(.up)) == [.select(index: 1)])
        #expect(machine.handle(.command(.up)) == [])  // top edge
        #expect(machine.handle(.command(.down)) == [.select(index: 4)])
        #expect(machine.handle(.command(.commit)) == [.hide, .activate(index: 4)])
    }

    @Test mutating func withoutColumnsUpAndDownDoNothing() {
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
