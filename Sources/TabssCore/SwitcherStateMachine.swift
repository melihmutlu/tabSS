public enum SwitcherEvent: Equatable, Sendable {
    case open(reverse: Bool, itemCount: Int, firstItemIsFocused: Bool)
    case command(SwitcherCommand)
    case showDelayElapsed(session: Int)
    case pointerHovered(index: Int)
    case pointerClicked(index: Int)
}

public enum SwitcherEffect: Equatable, Sendable {
    case scheduleShow(session: Int, delay: Duration)
    case show(selectedIndex: Int)
    case select(index: Int)
    case hide
    case activate(index: Int)
}

/// Pure switcher lifecycle: idle → armed (Cmd+Tab pressed, panel pending) → visible.
public struct SwitcherStateMachine: Sendable {
    // Long enough that a quick Cmd+Tab tap never flashes the panel, short enough to feel instant.
    public static let showDelay: Duration = .milliseconds(80)
    // How often a visible panel rechecks Cmd, in case its release was never reported.
    public static let releaseCheckInterval: Duration = .milliseconds(250)

    enum Phase: Equatable, Sendable {
        case idle
        case armed(Selection)
        case visible(Selection)
    }

    private(set) var phase: Phase = .idle
    private(set) var session = 0

    public init() {}

    public var isActive: Bool { phase != .idle }

    public var selectedIndex: Int? {
        switch phase {
        case .idle: nil
        case let .armed(selection), let .visible(selection): selection.index
        }
    }

    public mutating func handle(_ event: SwitcherEvent) -> [SwitcherEffect] {
        switch (phase, event) {
        case let (.idle, .open(reverse, itemCount, firstItemIsFocused)):
            return open(itemCount: itemCount, reverse: reverse, firstItemIsFocused: firstItemIsFocused)
        case (.idle, _):
            return []
        case let (.armed(selection), .showDelayElapsed(session)) where session == self.session:
            phase = .visible(selection)
            return [.show(selectedIndex: selection.index)]
        case (_, .showDelayElapsed):
            return []
        case (_, .open):
            return []
        case let (_, .command(command)):
            return apply(command)
        case let (.visible(selection), .pointerHovered(index)) where selection.contains(index):
            return move { $0.select(index) }
        case let (.visible(selection), .pointerClicked(index)) where selection.contains(index):
            _ = move { $0.select(index) }
            return finish(activating: true)
        case (_, .pointerHovered), (_, .pointerClicked):
            return []
        }
    }

    private mutating func open(itemCount: Int, reverse: Bool, firstItemIsFocused: Bool) -> [SwitcherEffect] {
        guard itemCount > 0 else { return [] }
        // Forward starts at the previous window; if nothing is focused (e.g. its last window just closed), at the first.
        let initialIndex = reverse ? itemCount - 1 : (firstItemIsFocused ? 1 : 0)
        session += 1
        phase = .armed(Selection(count: itemCount, index: initialIndex))
        return [.scheduleShow(session: session, delay: Self.showDelay)]
    }

    private mutating func apply(_ command: SwitcherCommand) -> [SwitcherEffect] {
        switch command {
        case .next: move { $0.next() }
        case .previous: move { $0.previous() }
        case .cancel: finish(activating: false)
        case .commit: finish(activating: true)
        }
    }

    private mutating func move(_ change: (inout Selection) -> Void) -> [SwitcherEffect] {
        switch phase {
        case .idle:
            return []
        case var .armed(selection):
            change(&selection)
            phase = .armed(selection)
            return []
        case var .visible(selection):
            let before = selection.index
            change(&selection)
            phase = .visible(selection)
            return selection.index == before ? [] : [.select(index: selection.index)]
        }
    }

    private mutating func finish(activating: Bool) -> [SwitcherEffect] {
        let wasVisible: Bool
        let selection: Selection
        switch phase {
        case .idle: return []
        case let .armed(current): (wasVisible, selection) = (false, current)
        case let .visible(current): (wasVisible, selection) = (true, current)
        }
        phase = .idle
        var effects: [SwitcherEffect] = wasVisible ? [.hide] : []
        if activating {
            effects.append(.activate(index: selection.index))
        }
        return effects
    }
}
