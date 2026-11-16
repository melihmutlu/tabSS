import Testing
@testable import TabssCore

/// Column memory ("vertical anchor") semantics for Up/Down.
///
/// Every case uses 4 columns and 11 items, whose last row is centered:
///
///     0   1   2   3
///     4   5   6   7
///       8   9   10        (drawn at 0.5, 1.5, 2.5)
///
/// Each expectation is chosen so that forgetting (or wrongly keeping) the anchor lands on a different tile.
struct ColumnMemoryAnchorTests {
    private func selection(at index: Int) -> Selection {
        Selection(count: 11, index: index, columns: 4)
    }

    // MARK: Blocked moves at an edge keep the anchor

    @Test func anchorSurvivesABlockedMoveAtTheBottom() {
        var s = selection(at: 1)
        s.down(); #expect(s.index == 5)
        s.down(); #expect(s.index == 8)  // tie between 8 and 9 goes left
        s.down(); #expect(s.index == 8)  // bottom edge: stays
        s.down(); #expect(s.index == 8)
        s.up(); #expect(s.index == 5)    // without the anchor: 4 (8 is drawn at 0.5)
        s.up(); #expect(s.index == 1)
    }

    @Test func anchorSurvivesABlockedMoveAtTheTop() {
        var s = selection(at: 9)          // drawn at 1.5
        s.up(); #expect(s.index == 5)
        s.up(); #expect(s.index == 1)
        s.up(); #expect(s.index == 1)     // top edge: stays
        s.down(); #expect(s.index == 5)
        s.down(); #expect(s.index == 9)   // without the anchor: 8 (5 is drawn at 1, between 8 and 9)
    }

    // MARK: Mixed up/down chains

    @Test func mixedChainsKeepTheStartingColumn() {
        var s = selection(at: 2)
        let steps: [(down: Bool, expected: Int)] = [
            (true, 6), (false, 2), (true, 6), (true, 9), (false, 6), (true, 9), (false, 6), (false, 2),
        ]
        for (step, (down, expected)) in steps.enumerated() {
            down ? s.down() : s.up()
            #expect(s.index == expected, "step \(step)")
        }
    }

    @Test func longRandomChainsAlwaysReturnHome() {
        // From any start, any run of up/down presses (edge stops included) that ends back in the start row
        // ends on the start tile.
        var generator = SystemRandomNumberGenerator()
        for start in 0..<11 {
            let grid = GridPosition(count: 11, columns: 4)
            for _ in 0..<200 {
                var s = selection(at: start)
                for _ in 0..<Int.random(in: 1...12, using: &generator) {
                    Bool.random(using: &generator) ? s.down() : s.up()
                }
                // Walk back to the starting row.
                while grid.row(of: s.index) < grid.row(of: start) { s.down() }
                while grid.row(of: s.index) > grid.row(of: start) { s.up() }
                #expect(s.index == start, "start \(start)")
            }
        }
    }

    // MARK: Sideways moves and explicit selection reset the anchor

    @Test func nextResetsTheAnchor() {
        var s = selection(at: 3)
        s.down(); s.down(); #expect(s.index == 10)
        s.next(); #expect(s.index == 0)   // wraps
        s.down(); #expect(s.index == 4)   // a stale anchor (column 3) would give 7
    }

    @Test func previousResetsTheAnchor() {
        var s = selection(at: 1)
        s.down(); s.down(); #expect(s.index == 8)
        s.previous(); #expect(s.index == 7)
        s.up(); #expect(s.index == 3)     // a stale anchor (column 1) would give 1
    }

    @Test func nextThenPreviousBackToTheSameTileStillResets() {
        var s = selection(at: 1)
        s.down(); s.down(); #expect(s.index == 8)
        s.next(); s.previous(); #expect(s.index == 8)
        s.up(); #expect(s.index == 4)     // fresh run from 0.5: tie 4/5 goes left; a stale anchor would give 5
    }

    @Test func selectResetsTheAnchor() {
        var s = selection(at: 1)
        s.down(); s.down(); #expect(s.index == 8)
        s.select(10)
        s.up(); #expect(s.index == 6)     // fresh run from 2.5: tie 6/7 goes left; a stale anchor would give 5
    }

    @Test func selectingTheCurrentTileResetsTheAnchor() {
        var s = selection(at: 1)
        s.down(); s.down(); #expect(s.index == 8)
        s.select(8)
        s.up(); #expect(s.index == 4)     // a stale anchor would give 5
    }

    // MARK: Through the state machine

    private func commitIndex(_ machine: inout SwitcherStateMachine) -> Int? {
        machine.handle(.command(.commit)).compactMap {
            if case let .activate(index) = $0 { index } else { nil }
        }.first
    }

    @Test(arguments: [false, true])
    func reverseOpenRemembersTheLastTilesColumn(visible: Bool) {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.open(reverse: true, itemCount: 11, firstItemIsFocused: true, columns: 4))
        #expect(machine.selectedIndex == 10)
        if visible { _ = machine.handle(.showDelayElapsed(session: machine.session)) }
        for (command, expected) in [(SwitcherCommand.up, 6), (.up, 2), (.down, 6), (.down, 10)] {
            _ = machine.handle(.command(command))
            #expect(machine.selectedIndex == expected)  // without the anchor the last Down gives 9
        }
        #expect(commitIndex(&machine) == 10)
    }

    @Test func reopeningStartsWithoutAnAnchor() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.open(reverse: false, itemCount: 11, firstItemIsFocused: true, columns: 4))
        _ = machine.handle(.command(.down))
        _ = machine.handle(.command(.down))
        #expect(commitIndex(&machine) == 8)
        _ = machine.handle(.open(reverse: true, itemCount: 11, firstItemIsFocused: true, columns: 4))
        _ = machine.handle(.command(.up))
        #expect(machine.selectedIndex == 6)            // from 10 (2.5), not from column 1
    }

    @Test func hoverResetsTheAnchorEvenOnTheSelectedTile() {
        var machine = SwitcherStateMachine()
        _ = machine.handle(.open(reverse: false, itemCount: 11, firstItemIsFocused: true, columns: 4))
        _ = machine.handle(.showDelayElapsed(session: machine.session))
        _ = machine.handle(.command(.down))
        _ = machine.handle(.command(.down))
        #expect(machine.selectedIndex == 8)
        #expect(machine.handle(.pointerHovered(index: 8)).isEmpty)
        _ = machine.handle(.command(.up))
        #expect(machine.selectedIndex == 4)            // a stale anchor (column 1) would give 5
    }
}
