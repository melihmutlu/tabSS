/// Where Cmd stands for a session, as seen by the event tap (the authority) and the hardware.
public enum CommandKeyState: Sendable {
    case held
    /// The tap already routed the release; its commit or cancel is still on the way.
    case releaseSeen
    /// Cmd is up but the tap never saw it go up.
    case releaseMissed
}

/// Drives one switcher session: snapshots entries on open, runs the state machine and performs its effects.
/// Sessions are numbered by the event tap; actions for any other session are stale and ignored.
@MainActor
public final class SwitcherController<Entry> {
    public struct Snapshot {
        public let entries: [Entry]
        public let firstItemIsFocused: Bool

        public init(entries: [Entry], firstItemIsFocused: Bool) {
            self.entries = entries
            self.firstItemIsFocused = firstItemIsFocused
        }
    }

    /// Called synchronously on the main actor; they must stay fast.
    public struct Dependencies {
        let snapshot: () -> Snapshot
        let show: (_ entries: [Entry], _ selectedIndex: Int) -> Void
        let select: (_ index: Int) -> Void
        let hide: () -> Void
        let activate: (Entry) -> Void
        let sessionEnded: (_ session: Int) -> Void
        let commandKeyState: (_ session: Int) -> CommandKeyState
        let schedule: (_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> Void

        public init(
            snapshot: @escaping () -> Snapshot,
            show: @escaping ([Entry], Int) -> Void,
            select: @escaping (Int) -> Void,
            hide: @escaping () -> Void,
            activate: @escaping (Entry) -> Void,
            sessionEnded: @escaping (Int) -> Void,
            commandKeyState: @escaping (Int) -> CommandKeyState,
            schedule: @escaping (Duration, @escaping @MainActor () -> Void) -> Void
        ) {
            self.snapshot = snapshot
            self.show = show
            self.select = select
            self.hide = hide
            self.activate = activate
            self.sessionEnded = sessionEnded
            self.commandKeyState = commandKeyState
            self.schedule = schedule
        }
    }

    private let dependencies: Dependencies
    private var machine = SwitcherStateMachine()
    private var entries: [Entry] = []
    private var keyboardSession = 0

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public var isActive: Bool { machine.isActive }

    public func handle(_ action: KeyAction, session: Int) {
        switch action {
        case let .open(reverse):
            guard !machine.isActive else { return }
            keyboardSession = session
            let snapshot = dependencies.snapshot()
            entries = snapshot.entries
            send(.open(reverse: reverse, itemCount: entries.count, firstItemIsFocused: snapshot.firstItemIsFocused))
        case let .command(command):
            guard session == keyboardSession else { return }
            send(.command(command))
        }
    }

    public func pointerHovered(at index: Int) {
        send(.pointerHovered(index: index))
    }

    public func pointerClicked(at index: Int) {
        send(.pointerClicked(index: index))
    }

    private func send(_ event: SwitcherEvent) {
        let wasActive = machine.isActive
        // Effects resolve indices against this event's entries, even if a dependency re-enters and opens anew.
        let sessionEntries = entries
        let effects = machine.handle(event)
        if !machine.isActive && (wasActive || event.isOpen) {
            entries = []
            // Before activating: the tap must stop treating keys as switcher keys right away.
            dependencies.sessionEnded(keyboardSession)
        }
        for effect in effects {
            perform(effect, entries: sessionEntries)
        }
    }

    private func perform(_ effect: SwitcherEffect, entries: [Entry]) {
        switch effect {
        case let .scheduleShow(showSession, delay):
            dependencies.schedule(delay) { [weak self] in self?.showDelayElapsed(showSession: showSession) }
        case let .show(selectedIndex):
            dependencies.show(entries, selectedIndex)
        case let .select(index):
            dependencies.select(index)
        case .hide:
            dependencies.hide()
        case let .activate(index):
            dependencies.activate(entries[index])
        }
    }

    /// `showSession` is the state machine's own counter, which guards against stale timers.
    private func showDelayElapsed(showSession: Int) {
        guard machine.isActive, showSession == machine.session else { return }
        switch dependencies.commandKeyState(keyboardSession) {
        case .held:
            send(.showDelayElapsed(session: showSession))
        case .releaseMissed:
            send(.command(.commit))
        case .releaseSeen:
            break
        }
    }
}

private extension SwitcherEvent {
    var isOpen: Bool {
        if case .open = self { true } else { false }
    }
}
