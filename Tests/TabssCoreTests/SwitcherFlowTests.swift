import Testing
@testable import TabssCore

/// Drives KeyRouter and SwitcherStateMachine together, the way the hotkey glue wires them.
struct SwitcherFlowTests {
    private var router = KeyRouter()
    private var machine = SwitcherStateMachine()
    private let itemCount = 4

    private mutating func send(_ input: KeyInput) -> (consumed: Bool, effects: [SwitcherEffect]) {
        let decision = router.route(input, isSwitching: machine.isActive)
        guard let action = decision.action else { return (decision.consumesEvent, []) }
        let event: SwitcherEvent
        switch action {
        case let .open(reverse): event = .open(reverse: reverse, itemCount: itemCount, firstItemIsFocused: true)
        case let .command(command): event = .command(command)
        }
        return (decision.consumesEvent, machine.handle(event))
    }

    private static let show = SwitcherEffect.scheduleShow(session: 1, delay: SwitcherStateMachine.showDelay)

    @Test mutating func quickTapSwitchesToPreviousWithoutPanel() {
        #expect(send(.modifiersChanged(.command)) == (false, []))
        #expect(send(.keyDown(keyCode: KeyCode.tab, modifiers: .command)) == (true, [Self.show]))
        #expect(send(.keyUp(keyCode: KeyCode.tab)) == (true, []))
        #expect(send(.modifiersChanged([])) == (false, [.activate(index: 1)]))
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [])
    }

    @Test mutating func holdTabTwiceThenReleaseActivatesThirdItem() {
        _ = send(.keyDown(keyCode: KeyCode.tab, modifiers: .command))
        _ = send(.keyUp(keyCode: KeyCode.tab))
        #expect(machine.handle(.showDelayElapsed(session: 1)) == [.show(selectedIndex: 1)])
        #expect(send(.keyDown(keyCode: KeyCode.tab, modifiers: .command)) == (true, [.select(index: 2)]))
        #expect(send(.keyUp(keyCode: KeyCode.tab)) == (true, []))
        #expect(send(.modifiersChanged([])) == (false, [.hide, .activate(index: 2)]))
    }

    @Test mutating func reverseQuickTapActivatesLastItem() {
        _ = send(.keyDown(keyCode: KeyCode.tab, modifiers: [.command, .shift]))
        #expect(send(.modifiersChanged([])) == (false, [.activate(index: itemCount - 1)]))
        #expect(send(.keyUp(keyCode: KeyCode.tab)) == (true, []))
    }

    @Test mutating func escapeCancelsAndLaterCommandReleaseDoesNothing() {
        _ = send(.keyDown(keyCode: KeyCode.tab, modifiers: .command))
        _ = send(.keyUp(keyCode: KeyCode.tab))
        #expect(send(.keyDown(keyCode: KeyCode.escape, modifiers: .command)) == (true, []))
        #expect(!machine.isActive)
        #expect(send(.keyUp(keyCode: KeyCode.escape)) == (true, []))
        #expect(send(.modifiersChanged([])) == (false, []))
    }

    @Test mutating func cmdTabAgainAfterEscapeReopens() {
        _ = send(.keyDown(keyCode: KeyCode.tab, modifiers: .command))
        _ = send(.keyUp(keyCode: KeyCode.tab))
        _ = send(.keyDown(keyCode: KeyCode.escape, modifiers: .command))
        _ = send(.keyUp(keyCode: KeyCode.escape))
        let reopened = send(.keyDown(keyCode: KeyCode.tab, modifiers: .command))
        #expect(reopened == (true, [.scheduleShow(session: 2, delay: SwitcherStateMachine.showDelay)]))
        #expect(machine.selectedIndex == 1)
    }

    @Test mutating func holdingTabAfterEscapeNeitherReopensNorReachesApp() {
        _ = send(.keyDown(keyCode: KeyCode.tab, modifiers: .command))
        #expect(send(.keyDown(keyCode: KeyCode.escape, modifiers: .command)) == (true, []))
        // Cmd and Tab are still held: Tab's auto-repeat must not reopen the switcher or reach the app.
        for _ in 0..<3 {
            #expect(send(.keyDown(keyCode: KeyCode.tab, modifiers: .command, isRepeat: true)) == (true, []))
            #expect(!machine.isActive)
        }
        #expect(send(.keyUp(keyCode: KeyCode.tab)) == (true, []))
        #expect(send(.keyUp(keyCode: KeyCode.escape)) == (true, []))
    }

    @Test mutating func missedCommandReleaseCommitsOnNextKeystrokeAndDeliversIt() {
        _ = send(.keyDown(keyCode: KeyCode.tab, modifiers: .command))
        _ = send(.keyUp(keyCode: KeyCode.tab))
        let a: UInt16 = 0
        #expect(send(.keyDown(keyCode: a, modifiers: [])) == (false, [.activate(index: 1)]))
        #expect(send(.keyUp(keyCode: a)) == (false, []))
        #expect(!machine.isActive)
    }
}
