import Testing
@testable import TabssCore

/// Repeated quick Cmd+Tab taps must alternate between the two most recent windows even when macOS reports
/// focus changes late. The app records each switch in the registry as it activates (`WindowStore.noteSwitch`);
/// this checks that the controller activates before the next session snapshots, so that record is seen.
@MainActor
final class QuickSwitchHarness {
    var tap = HotkeyState()
    var registry: WindowRegistry<Int, Int>
    let owners: [Int: Int]
    private(set) var activated: [Int] = []
    /// Focus reports macOS has not delivered yet.
    private(set) var pendingFocusReports: [Int] = []
    private var mainQueue: [(KeyAction, Int)] = []

    init(owners: [Int: Int], zOrder: [Int]) {
        self.owners = owners
        registry = WindowRegistry(zOrder: zOrder)
        for window in zOrder { registry.add(window, of: owners[window]!) }
        registry.activate(owners[zOrder[0]]!, focusedWindow: zOrder[0])
    }

    lazy var controller = SwitcherController<Int>(dependencies: .init(
        snapshot: { [unowned self] in
            let windows = registry.items(runningApps: []).compactMap { item -> Int? in
                if case let .window(id) = item { id } else { nil }
            }
            return .init(entries: windows, firstItemIsFocused: windows.first == registry.focusedWindow)
        },
        show: { _, _ in },
        select: { _ in },
        hide: {},
        activate: { [unowned self] window in
            registry.activate(owners[window]!, focusedWindow: window)  // as WindowStore.noteSwitch does
            activated.append(window)
            pendingFocusReports.append(window)
        },
        sessionEnded: { [unowned self] in tap.end($0) },
        commandKeyState: { [unowned self] in tap.isOpen($0) ? .held : .releaseSeen },
        schedule: { _, _ in }
    ))

    func quickTap() {
        for input: KeyInput in [
            .modifiersChanged(.command), .keyDown(keyCode: KeyCode.tab, modifiers: .command),
            .keyUp(keyCode: KeyCode.tab), .modifiersChanged([]),
        ] {
            let routed = tap.route(input)
            if let action = routed.decision.action { mainQueue.append((action, routed.session)) }
        }
    }

    func drain() {
        let pending = mainQueue
        mainQueue = []
        for (action, session) in pending { controller.handle(action, session: session) }
    }

    func deliverFocusReports() {
        for window in pendingFocusReports { registry.activate(owners[window]!, focusedWindow: window) }
        pendingFocusReports = []
    }
}

@MainActor
struct QuickSwitchRecencyTests {
    private let h = QuickSwitchHarness(owners: [1: 10, 2: 20, 3: 10], zOrder: [1, 2, 3])

    @Test func quickTapsAlternateBeforeFocusReportsArrive() {
        for _ in 0..<4 {
            h.quickTap()
            h.drain()
        }
        #expect(h.activated == [2, 1, 2, 1])
        h.deliverFocusReports()
        #expect(h.registry.focusedWindow == 1)
        #expect(h.registry.items(runningApps: []).first == .window(1))
    }

    // Main was busy while two taps were routed: the second session snapshots after the first activated.
    @Test func tapsQueuedOnABusyMainActorStillAlternate() {
        h.quickTap()
        h.quickTap()
        h.quickTap()
        h.drain()
        #expect(h.activated == [2, 1, 2])
        #expect(!h.tap.isSwitching && !h.controller.isActive)
    }

    @Test func windowsOfTheSameAppAlternateToo() {
        let h = QuickSwitchHarness(owners: [1: 10, 3: 10, 2: 20], zOrder: [1, 3, 2])
        for _ in 0..<3 {
            h.quickTap()
            h.drain()
        }
        #expect(h.activated == [3, 1, 3])
    }
}
