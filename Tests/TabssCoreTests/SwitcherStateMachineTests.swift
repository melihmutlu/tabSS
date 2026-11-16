import Testing
@testable import TabssCore

struct SwitcherStateMachineTests {
    private var machine = SwitcherStateMachine()

    private mutating func open(count: Int, reverse: Bool = false, firstItemIsFocused: Bool = true) -> [SwitcherEffect] {
        machine.handle(.open(reverse: reverse, itemCount: count, firstItemIsFocused: firstItemIsFocused))
    }

    private mutating func send(_ command: SwitcherCommand) -> [SwitcherEffect] {
        machine.handle(.command(command))
    }

    @Test mutating func openArmsAndSchedulesShow() {
        #expect(open(count: 3) == [.scheduleShow(session: 1, delay: SwitcherStateMachine.showDelay)])
        #expect(machine.isActive)
        #expect(machine.selectedIndex == 1)
    }

    @Test mutating func reverseOpenSelectsLastItem() {
        _ = open(count: 4, reverse: true)
        #expect(machine.selectedIndex == 3)
    }

    @Test mutating func singleItemSelectsIt() {
        _ = open(count: 1)
        #expect(machine.selectedIndex == 0)
    }

    @Test mutating func quickTapActivatesPreviousWithoutShowing() {
        _ = open(count: 3)
        #expect(send(.commit) == [.activate(index: 1)])
        #expect(!machine.isActive)
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [])
    }

    @Test mutating func showsAfterDelayThenHidesOnCommit() {
        _ = open(count: 3)
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [.show(selectedIndex: 1)])
        #expect(send(.next) == [.select(index: 2)])
        #expect(send(.commit) == [.hide, .activate(index: 2)])
    }

    @Test mutating func navigationBeforeShowIsTrackedSilently() {
        _ = open(count: 3)
        #expect(send(.next) == [])
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [.show(selectedIndex: 2)])
    }

    @Test mutating func staleShowTimerIsIgnored() {
        _ = open(count: 3)
        _ = send(.cancel)
        _ = open(count: 3)
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [])
        #expect(machine.handle(.showDelayElapsed(session: 2)) == [.show(selectedIndex: 1)])
    }

    @Test mutating func cancelHidesWithoutActivating() {
        _ = open(count: 3)
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(send(.cancel) == [.hide])
        #expect(!machine.isActive)
    }

    @Test mutating func emptyListDoesNotOpen() {
        #expect(open(count: 0) == [])
        #expect(!machine.isActive)
        #expect(send(.commit) == [])
    }

    @Test mutating func quickTapTargetsFirstItemWhenNothingIsFocused() {
        _ = open(count: 3, firstItemIsFocused: false)
        #expect(send(.commit) == [.activate(index: 0)])
    }

    @Test mutating func pointerSelectsAndCommitsOnlyWhenVisible() {
        _ = open(count: 3)
        #expect(machine.handle(.pointerHovered(index: 0)) == [])
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(machine.handle(.pointerHovered(index: 0)) == [.select(index: 0)])
        #expect(machine.handle(.pointerHovered(index: 0)) == [])
        #expect(machine.handle(.pointerClicked(index: 2)) == [.hide, .activate(index: 2)])
    }

    @Test mutating func idleIgnoresEverythingButOpen() {
        #expect(send(.next) == [])
        #expect(send(.commit) == [])
        #expect(machine.handle(.pointerClicked(index: 0)) == [])
    }

    @Test mutating func openWhileActiveIsIgnored() {
        _ = open(count: 3)
        #expect(open(count: 5) == [])
        #expect(machine.selectedIndex == 1)
    }

    @Test mutating func cancelWhileArmedEmitsNothingAndGoesIdle() {
        _ = open(count: 3)
        #expect(send(.cancel) == [])
        #expect(!machine.isActive)
        #expect(machine.selectedIndex == nil)
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [])
    }

    @Test mutating func duplicateShowTimerWhileVisibleIsIgnored() {
        _ = open(count: 3)
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [])
        #expect(send(.commit) == [.hide, .activate(index: 1)])
    }

    @Test mutating func previousWrapsSilentlyWhileArmed() {
        _ = open(count: 3)
        #expect(send(.previous) == [])
        #expect(send(.previous) == [])
        #expect(machine.selectedIndex == 2)
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [.show(selectedIndex: 2)])
    }

    @Test mutating func navigationWrapsWhileVisible() {
        _ = open(count: 3)
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(send(.next) == [.select(index: 2)])
        #expect(send(.next) == [.select(index: 0)])
        #expect(send(.previous) == [.select(index: 2)])
    }

    @Test mutating func navigationOnSingleItemEmitsNoSelect() {
        _ = open(count: 1)
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(send(.next) == [])
        #expect(send(.previous) == [])
        #expect(send(.commit) == [.hide, .activate(index: 0)])
    }

    @Test mutating func reverseOpenEdgeCounts() {
        _ = open(count: 2, reverse: true)
        #expect(machine.selectedIndex == 1)
        _ = send(.cancel)
        #expect(open(count: 0, reverse: true) == [])
        #expect(machine.selectedIndex == nil)
    }

    @Test mutating func outOfRangePointerEventsAreIgnored() {
        _ = open(count: 3)
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(machine.handle(.pointerHovered(index: 3)) == [])
        #expect(machine.handle(.pointerClicked(index: -1)) == [])
        #expect(machine.isActive)
        #expect(machine.selectedIndex == 1)
    }

    @Test mutating func openWhileVisibleIsIgnored() {
        _ = open(count: 3)
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(open(count: 5, reverse: true) == [])
        #expect(machine.selectedIndex == 1)
        #expect(send(.cancel) == [.hide])
    }

    @Test mutating func pointerEventsWhileArmedLeaveSelectionUntouched() {
        _ = open(count: 3)
        #expect(machine.handle(.pointerClicked(index: 0)) == [])
        #expect(machine.isActive)
        #expect(send(.commit) == [.activate(index: 1)])
    }

    @Test mutating func clickOnAlreadySelectedTileActivatesIt() {
        _ = open(count: 3)
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(machine.handle(.pointerClicked(index: 1)) == [.hide, .activate(index: 1)])
        #expect(!machine.isActive)
    }

    @Test mutating func eventsAfterFinishAreIgnored() {
        _ = open(count: 3)
        _ = machine.handle(.showDelayElapsed(session: 1))
        _ = send(.commit)
        #expect(send(.commit) == [])
        #expect(send(.cancel) == [])
        #expect(machine.handle(.pointerHovered(index: 0)) == [])
    }

    @Test mutating func quickDoubleTabActivatesThirdItemWithoutShowing() {
        _ = machine.handle(.open(reverse: false, itemCount: 3, firstItemIsFocused: true))
        #expect(machine.handle(.command(.next)) == [])
        #expect(machine.handle(.command(.commit)) == [.activate(index: 2)])
    }

    @Test mutating func hoverThenKeyboardCommitActivatesHoveredTile() {
        _ = machine.handle(.open(reverse: false, itemCount: 3, firstItemIsFocused: true))
        _ = machine.handle(.showDelayElapsed(session: 1))
        #expect(machine.handle(.pointerHovered(index: 0)) == [.select(index: 0)])
        #expect(machine.handle(.command(.previous)) == [.select(index: 2)])
        #expect(machine.handle(.command(.commit)) == [.hide, .activate(index: 2)])
    }

    @Test mutating func reopenAfterFinishStartsFromSecondItemAgain() {
        _ = machine.handle(.open(reverse: false, itemCount: 3, firstItemIsFocused: true))
        _ = machine.handle(.command(.previous))
        _ = machine.handle(.command(.cancel))
        _ = machine.handle(.open(reverse: false, itemCount: 5, firstItemIsFocused: true))
        #expect(machine.selectedIndex == 1)
        #expect(machine.handle(.showDelayElapsed(session: 2)) == [.show(selectedIndex: 1)])
    }
}
