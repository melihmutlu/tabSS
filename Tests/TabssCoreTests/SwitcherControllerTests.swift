import Testing
@testable import TabssCore

@MainActor
final class FakeSwitcherEnvironment {
    enum Call: Equatable {
        case show([String], Int)
        case select(Int)
        case hide
        case activate(String)
    }

    var entries = ["A", "B", "C"]
    var firstItemIsFocused = true
    var commandKeyState = CommandKeyState.held
    private(set) var queriedSessions: [Int] = []
    /// Runs inside `hide`, to simulate a dependency that calls back into the controller synchronously.
    var onHide: (() -> Void)?
    var onActivate: (() -> Void)?
    private(set) var calls: [Call] = []
    private(set) var endedSessions: [Int] = []
    private(set) var scheduledDelays: [Duration] = []
    private var scheduled: [@MainActor () -> Void] = []
    private(set) var session = 0

    lazy var controller = SwitcherController<String>(dependencies: .init(
        snapshot: { [unowned self] in .init(entries: entries, firstItemIsFocused: firstItemIsFocused) },
        show: { [unowned self] in calls.append(.show($0, $1)) },
        select: { [unowned self] in calls.append(.select($0)) },
        hide: { [unowned self] in
            calls.append(.hide)
            onHide?()
        },
        activate: { [unowned self] in
            calls.append(.activate($0))
            onActivate?()
        },
        sessionEnded: { [unowned self] in endedSessions.append($0) },
        commandKeyState: { [unowned self] in
            queriedSessions.append($0)
            return commandKeyState
        },
        schedule: { [unowned self] delay, action in
            scheduledDelays.append(delay)
            scheduled.append(action)
        }
    ))

    /// Mimics the event tap: every open starts a new keyboard session.
    func open(reverse: Bool = false) {
        session += 1
        controller.handle(.open(reverse: reverse), session: session)
    }

    func send(_ command: SwitcherCommand, session explicitSession: Int? = nil) {
        controller.handle(.command(command), session: explicitSession ?? session)
    }

    func fireScheduled() {
        let pending = scheduled
        scheduled = []
        pending.forEach { $0() }
    }

    func fireOldestScheduled() {
        scheduled.removeFirst()()
    }
}

@MainActor
struct SwitcherControllerTests {
    private let env = FakeSwitcherEnvironment()

    @Test func quickTapActivatesPreviousEntryWithoutShowing() {
        env.open()
        env.send(.commit)
        env.fireScheduled()
        #expect(env.calls == [.activate("B")])
        #expect(!env.controller.isActive)
    }

    @Test func showsAfterDelayWhileCommandIsHeld() {
        env.open()
        #expect(env.scheduledDelays == [SwitcherStateMachine.showDelay])
        env.fireScheduled()
        env.send(.next)
        env.send(.commit)
        #expect(env.calls == [.show(["A", "B", "C"], 1), .select(2), .hide, .activate("C")])
    }

    @Test func missedCommandReleaseCommitsInsteadOfShowing() {
        env.open()
        env.commandKeyState = .releaseMissed
        env.fireScheduled()
        #expect(env.calls == [.activate("B")])
        #expect(!env.controller.isActive)
    }

    // Main was busy: the tap already routed Tab and the release, but they are still queued behind the timer.
    @Test func timerDefersToReleaseTheTapAlreadySaw() {
        env.open()
        env.commandKeyState = .releaseSeen
        env.fireScheduled()
        #expect(env.calls.isEmpty)
        env.send(.next)
        env.send(.commit)
        #expect(env.calls == [.activate("C")])
    }

    @Test func timerDefersToQueuedEscape() {
        env.open()
        env.commandKeyState = .releaseSeen
        env.fireScheduled()
        env.send(.cancel)
        #expect(env.calls.isEmpty)
        #expect(!env.controller.isActive)
    }

    @Test func commandsForAnotherSessionAreIgnored() {
        env.open()
        env.send(.next, session: env.session - 1)
        env.send(.commit, session: env.session + 1)
        #expect(env.controller.isActive)
        env.send(.commit)
        #expect(env.calls == [.activate("B")])
    }

    @Test func emptySnapshotDoesNotOpenButEndsTheTapSession() {
        env.entries = []
        env.open()
        #expect(!env.controller.isActive)
        #expect(env.scheduledDelays.isEmpty)
        #expect(env.endedSessions == [1])
    }

    @Test func unfocusedFirstEntryIsTheQuickTapTarget() {
        env.firstItemIsFocused = false
        env.open()
        env.send(.commit)
        #expect(env.calls == [.activate("A")])
    }

    @Test func snapshotIsTakenAtOpenAndKeptForTheSession() {
        env.open(reverse: true)
        env.entries = ["X"]
        env.send(.commit)
        #expect(env.calls == [.activate("C")])
    }

    @Test func pointerClickActivatesClickedEntry() {
        env.open()
        env.fireScheduled()
        env.controller.pointerHovered(at: 0)
        env.controller.pointerClicked(at: 2)
        #expect(env.calls == [.show(["A", "B", "C"], 1), .select(0), .hide, .activate("C")])
    }

    @Test func sessionEndIsReportedOnceWithItsNumber() {
        env.open()
        env.send(.cancel)
        env.open()
        env.fireScheduled()
        env.controller.pointerClicked(at: 0)
        env.send(.commit)
        env.controller.pointerHovered(at: 0)
        #expect(env.endedSessions == [1, 2])
    }

    // The tap stops swallowing switcher keys on `sessionEnded`, so it must never fire mid-session.
    @Test func sessionEndIsNotReportedWhileTheSessionContinues() {
        env.open()
        env.fireScheduled()
        env.send(.next)
        env.send(.previous)
        env.controller.pointerHovered(at: 0)
        env.controller.pointerHovered(at: 99)
        env.controller.pointerClicked(at: 99)
        #expect(env.controller.isActive)
        #expect(env.endedSessions.isEmpty)
    }

    @Test(arguments: [false, true])
    func sessionEndIsReportedBeforeActivation(panelShown: Bool) {
        var endedBeforeActivation = false
        env.onActivate = { [env] in endedBeforeActivation = env.endedSessions == [1] }
        env.open()
        if panelShown { env.fireScheduled() }
        env.send(.commit)
        #expect(endedBeforeActivation)
    }

    // The tap numbers sessions independently of the state machine; an empty open makes the two diverge.
    @Test func timerAsksAboutTheKeyboardSession() {
        env.entries = []
        env.open()
        env.entries = ["A", "B"]
        env.open()
        env.fireScheduled()
        #expect(env.queriedSessions == [2])
        #expect(env.calls == [.show(["A", "B"], 1)])
    }

    @Test func staleShowTimerDoesNotAffectTheNextSession() {
        env.open()
        env.send(.commit)
        env.open(reverse: true)
        env.commandKeyState = .releaseMissed
        env.fireOldestScheduled()
        #expect(env.calls == [.activate("B")])
        #expect(env.controller.isActive)
        env.commandKeyState = .held
        env.fireOldestScheduled()
        #expect(env.calls == [.activate("B"), .show(["A", "B", "C"], 2)])
    }

    @Test func openWhileActiveKeepsTheSessionSnapshot() {
        env.open()
        env.entries = ["X", "Y"]
        env.controller.handle(.open(reverse: false), session: env.session)
        env.send(.commit)
        #expect(env.calls == [.activate("B")])
    }

    @Test func reentrantOpenDuringHideDoesNotRetargetActivation() {
        env.open()
        env.fireScheduled()
        env.onHide = { [env] in
            env.onHide = nil
            env.entries = ["X", "Y"]
            env.open()
        }
        env.send(.commit, session: 1)
        #expect(env.calls == [.show(["A", "B", "C"], 1), .hide, .activate("B")])
        #expect(env.controller.isActive)
        env.send(.commit)
        #expect(env.calls.last == .activate("Y"))
    }

    @Test func sessionSnapshotIsReleasedWhenSessionEnds() {
        final class Entry {}
        weak var lastEntry: Entry?
        let controller = SwitcherController<Entry>(dependencies: .init(
            snapshot: {
                let entry = Entry()
                lastEntry = entry
                return .init(entries: [entry], firstItemIsFocused: false)
            },
            show: { _, _ in },
            select: { _ in },
            hide: {},
            activate: { _ in },
            sessionEnded: { _ in },
            commandKeyState: { _ in .held },
            schedule: { _, _ in }
        ))
        controller.handle(.open(reverse: false), session: 1)
        #expect(lastEntry != nil)
        controller.handle(.command(.commit), session: 1)
        #expect(lastEntry == nil)
    }

    @Test func visiblePanelCommitsWhenAReleaseIsMissedLater() {
        env.open()
        env.fireOldestScheduled()  // shows the panel and starts watching Cmd
        #expect(env.scheduledDelays == [SwitcherStateMachine.showDelay, SwitcherStateMachine.releaseCheckInterval])
        env.fireOldestScheduled()  // still held: keeps watching
        env.commandKeyState = .releaseMissed
        env.fireOldestScheduled()
        #expect(env.calls == [.show(["A", "B", "C"], 1), .hide, .activate("B")])
        #expect(!env.controller.isActive)
    }

    @Test func releaseWatchStopsWhenTheSessionEnds() {
        env.open()
        env.fireOldestScheduled()
        env.send(.cancel)
        env.commandKeyState = .releaseMissed
        env.fireScheduled()
        #expect(env.calls == [.show(["A", "B", "C"], 1), .hide])
    }

    @Test func snapshotColumnsDriveUpAndDown() {
        // 2 columns, 5 items:  A B / C D / . E .
        var activated: [String] = []
        let controller = SwitcherController<String>(dependencies: .init(
            snapshot: { .init(entries: ["A", "B", "C", "D", "E"], firstItemIsFocused: true, columns: 2) },
            show: { _, _ in },
            select: { _ in },
            hide: {},
            activate: { activated.append($0) },
            sessionEnded: { _ in },
            commandKeyState: { _ in .held },
            schedule: { _, _ in }
        ))
        controller.handle(.open(reverse: false), session: 1)  // B
        controller.handle(.command(.down), session: 1)        // D
        controller.handle(.command(.down), session: 1)        // E, centered below C and D
        controller.handle(.command(.down), session: 1)        // bottom edge: stays on E
        controller.handle(.command(.up), session: 1)          // C (tie between C and D goes left)
        controller.handle(.command(.commit), session: 1)
        #expect(activated == ["C"])
    }
}
