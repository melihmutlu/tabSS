import Testing
@testable import TabssCore

struct HotkeyStateTests {
    private var state = HotkeyState()
    private let cmdTab = KeyInput.keyDown(keyCode: KeyCode.tab, modifiers: .command)

    @Test mutating func openStartsNumberedSessionAndCmdReleaseEndsIt() {
        #expect(state.route(cmdTab) == .init(decision: .open(reverse: false), session: 1))
        #expect(state.isOpen(1))
        #expect(state.route(cmdTab) == .init(decision: .consume(.next), session: 1))
        #expect(state.route(.modifiersChanged([])) == .init(decision: .observe(.commit), session: 1))
        #expect(!state.isSwitching)
        #expect(state.route(cmdTab).session == 2)
    }

    @Test mutating func escapeEndsSessionImmediately() {
        _ = state.route(cmdTab)
        _ = state.route(.keyDown(keyCode: KeyCode.escape, modifiers: .command))
        #expect(!state.isOpen(1))
        #expect(state.route(.keyDown(keyCode: 13, modifiers: .command)) == .init(decision: .passThrough, session: 1))
    }

    @Test mutating func mainCanEndOnlyTheCurrentSession() {
        _ = state.route(cmdTab)
        _ = state.route(.modifiersChanged([]))
        _ = state.route(cmdTab)
        state.end(1)
        #expect(state.isOpen(2))
        state.end(2)
        #expect(!state.isSwitching)
        #expect(state.route(.keyDown(keyCode: KeyCode.escape, modifiers: .command)).decision == .passThrough)
    }

    @Test mutating func isOpenRequiresTheMatchingSession() {
        _ = state.route(cmdTab)
        #expect(!state.isOpen(0))
        #expect(!state.isOpen(2))
    }

    @Test mutating func lostEventsCommitOnlyWhenCommandWentUp() {
        #expect(state.eventsMayHaveBeenLost(isCommandHeld: false) == nil)
        _ = state.route(cmdTab)
        #expect(state.eventsMayHaveBeenLost(isCommandHeld: true) == nil)
        #expect(state.isOpen(1))
        #expect(state.eventsMayHaveBeenLost(isCommandHeld: false) == .init(decision: .observe(.commit), session: 1))
        #expect(!state.isSwitching)
    }

    // Repeats and the key-up of a key held through the switch must stay swallowed after a tap re-enable.
    @Test mutating func lostEventsKeepSwallowedKeyUps() {
        _ = state.route(cmdTab)
        _ = state.eventsMayHaveBeenLost(isCommandHeld: false)
        #expect(state.route(.keyDown(keyCode: KeyCode.tab, modifiers: [], isRepeat: true)).decision == .consume())
        #expect(state.route(.keyUp(keyCode: KeyCode.tab)).decision == .consume())
    }
}
