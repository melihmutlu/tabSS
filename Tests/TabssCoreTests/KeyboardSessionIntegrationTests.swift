import CoreGraphics
import Testing
@testable import TabssCore

/// Wires HotkeyState (the tap's authority on sessions) to SwitcherController the way `Switcher` and
/// `HotkeyMonitor` do: actions are queued for the main actor in order, `sessionEnded` reaches back into the tap
/// state, and the Cmd check consults `isOpen`. SwitcherFlowTests drives the router from the state machine
/// instead, so it can't see the two sides disagree.
@MainActor
final class KeyboardSessionHarness {
    var tap = HotkeyState()
    var entries = ["A", "B", "C", "D"]
    var commandIsPhysicallyHeld = true
    private(set) var activated: [String] = []
    private(set) var shown: [Int] = []
    private var mainQueue: [(KeyAction, Int)] = []
    private var timers: [@MainActor () -> Void] = []

    lazy var controller = SwitcherController<String>(dependencies: .init(
        snapshot: { [unowned self] in .init(entries: entries, firstItemIsFocused: true) },
        show: { [unowned self] _, index in shown.append(index) },
        select: { _ in },
        hide: {},
        activate: { [unowned self] in activated.append($0) },
        sessionEnded: { [unowned self] in tap.end($0) },
        commandKeyState: { [unowned self] session in
            guard tap.isOpen(session) else { return .releaseSeen }
            return commandIsPhysicallyHeld ? .held : .releaseMissed
        },
        schedule: { [unowned self] _, action in timers.append(action) }
    ))

    /// Routes on the tap; returns whether the event was swallowed. Main does not run until `drain`.
    @discardableResult
    func route(_ input: KeyInput) -> Bool {
        let routed = tap.route(input)
        if let action = routed.decision.action { mainQueue.append((action, routed.session)) }
        return routed.decision.consumesEvent
    }

    func drain() {
        let pending = mainQueue
        mainQueue = []
        for (action, session) in pending { controller.handle(action, session: session) }
    }

    func fireTimers() {
        let pending = timers
        timers = []
        pending.forEach { $0() }
    }

    func cmdTab(shift: Bool = false) {
        route(.modifiersChanged(shift ? [.command, .shift] : .command))
        route(.keyDown(keyCode: KeyCode.tab, modifiers: shift ? [.command, .shift] : .command))
        route(.keyUp(keyCode: KeyCode.tab))
    }

    func releaseCommand() {
        commandIsPhysicallyHeld = false
        route(.modifiersChanged([]))
    }
}

@MainActor
struct KeyboardSessionIntegrationTests {
    private let h = KeyboardSessionHarness()

    // Main busy: several complete taps are routed before main runs; each must still be its own session.
    @Test func queuedBurstOfTapsActivatesOncePerTap() {
        for _ in 0..<3 {
            h.cmdTab()
            h.releaseCommand()
        }
        h.drain()
        h.fireTimers()
        #expect(h.activated == ["B", "B", "B"])  // the fake snapshot never changes focus
        #expect(h.shown.isEmpty)
        #expect(!h.tap.isSwitching && !h.controller.isActive)
    }

    @Test(arguments: [KeyCode.returnKey, KeyCode.keypadEnter])
    func returnCommitsAndHandsLaterCommandKeysBackToApps(key: UInt16) {
        h.cmdTab()
        h.drain()
        h.fireTimers()
        #expect(h.route(.keyDown(keyCode: key, modifiers: .command)))
        h.drain()
        #expect(h.activated == ["B"])
        #expect(!h.tap.isSwitching)
        let w: UInt16 = 13
        #expect(!h.route(.keyDown(keyCode: w, modifiers: .command)))
        #expect(h.route(.keyUp(keyCode: key)))
        h.releaseCommand()
        h.drain()
        #expect(h.activated == ["B"])
    }

    // A click finishes on main; the tap must stop swallowing Cmd shortcuts and let a new Cmd+Tab open.
    @Test func clickEndsTheTapSessionWhileCommandIsStillHeld() {
        h.cmdTab()
        h.drain()
        h.fireTimers()
        h.controller.pointerClicked(at: 3)
        #expect(h.activated == ["D"])
        #expect(!h.tap.isSwitching)
        let w: UInt16 = 13
        #expect(!h.route(.keyDown(keyCode: w, modifiers: .command)))
        #expect(h.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command)))
        h.drain()
        #expect(h.controller.isActive)
        h.releaseCommand()
        h.drain()
        #expect(h.activated == ["D", "B"])
    }

    @Test func emptySnapshotEndsTheTapSessionSoShortcutsPassThrough() {
        h.entries = []
        h.cmdTab()
        h.drain()
        #expect(!h.tap.isSwitching)
        let w: UInt16 = 13
        #expect(!h.route(.keyDown(keyCode: w, modifiers: .command)))
    }

    @Test func missedReleaseWhileVisibleClosesBothSides() {
        h.cmdTab()
        h.drain()
        h.fireTimers()  // shows, starts watching Cmd
        #expect(h.shown == [1])
        h.commandIsPhysicallyHeld = false  // the release never reaches the tap
        h.fireTimers()
        #expect(h.activated == ["B"])
        #expect(!h.tap.isSwitching && !h.controller.isActive)
    }

    // Tap disabled and re-enabled after Cmd went up: the recovered commit must be the only activation.
    @Test func lostEventsCommitIsDeliveredOnce() {
        h.cmdTab()
        h.drain()
        h.commandIsPhysicallyHeld = false
        if let routed = h.tap.eventsMayHaveBeenLost(isCommandHeld: false), let action = routed.decision.action {
            h.controller.handle(action, session: routed.session)
        }
        h.fireTimers()
        h.route(.modifiersChanged([]))
        h.drain()
        #expect(h.activated == ["B"])
    }

    @Test func shiftTabThenArrowsThenReleaseThroughTheTap() {
        h.cmdTab()
        h.drain()
        h.fireTimers()
        h.route(.keyDown(keyCode: KeyCode.tab, modifiers: [.command, .shift]))  // 1 -> 0
        h.route(.keyDown(keyCode: KeyCode.leftArrow, modifiers: .command))  // 0 -> 3
        h.route(.keyDown(keyCode: KeyCode.rightArrow, modifiers: .command))  // 3 -> 0
        h.route(.keyDown(keyCode: KeyCode.rightArrow, modifiers: .command))  // 0 -> 1
        h.route(.keyDown(keyCode: KeyCode.rightArrow, modifiers: .command))  // 1 -> 2
        h.releaseCommand()
        h.drain()
        #expect(h.activated == ["C"])
    }
}

struct SwitcherTimingTests {
    // The plan's 80 ms rule: other tests reference the constant symbolically, so a changed value would pass them.
    @Test func showDelayIsEightyMilliseconds() {
        #expect(SwitcherStateMachine.showDelay == .milliseconds(80))
    }

    @Test func releaseWatchIsSlowerThanTheShowDelay() {
        #expect(SwitcherStateMachine.releaseCheckInterval > SwitcherStateMachine.showDelay)
    }
}

struct TextAndGeometryRegressionTests {
    // Subdivision flags (England, Scotland, Wales) are built from invisible tag characters that must survive.
    @Test func subdivisionFlagEmojiSurvives() {
        let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        #expect(DisplayText.title("Go " + england, fallback: "") == "Go " + england)
    }

    @Test func emojiPresentationSelectorSurvives() {
        #expect(DisplayText.title("I \u{2764}\u{FE0F} it", fallback: "") == "I \u{2764}\u{FE0F} it")
    }

    @Test func invisibleFillerLettersFallBack() {
        #expect(DisplayText.title("\u{3164}\u{115F}", fallback: "Finder") == "Finder")
    }

    @Test func fittedSizeStaysInsideAFractionalBox() {
        let fitted = CGSize(width: 3, height: 2).aspectFitted(in: CGSize(width: 99.6, height: 200))
        #expect(fitted.width <= 99.6)
    }
}
