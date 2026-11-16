/// Keyboard state owned by the event tap thread: routes keys and tracks which switcher session is open.
/// The tap thread is the authority on Cmd being released; the main actor can only close a session it finished itself.
public struct HotkeyState: Sendable {
    public struct Routed: Equatable, Sendable {
        public let decision: KeyDecision
        public let session: Int
    }

    private var router = KeyRouter()
    public private(set) var session = 0
    public private(set) var isSwitching = false

    public init() {}

    public mutating func route(_ input: KeyInput) -> Routed {
        let decision = router.route(input, isSwitching: isSwitching)
        switch decision.action {
        case .open?:
            session += 1
            isSwitching = true
        case .command(.commit)?, .command(.cancel)?:
            isSwitching = false
        case .command?, nil:
            break
        }
        return Routed(decision: decision, session: session)
    }

    /// Call when the tap was disabled and may have missed events. If Cmd went up meanwhile, the release was
    /// missed: the session is committed here, so recovery never waits for a possibly busy main actor.
    public mutating func eventsMayHaveBeenLost(isCommandHeld: Bool) -> Routed? {
        guard isSwitching, !isCommandHeld else { return nil }
        isSwitching = false
        return Routed(decision: .observe(.commit), session: session)
    }

    public mutating func end(_ ended: Int) {
        if ended == session { isSwitching = false }
    }

    public func isOpen(_ candidate: Int) -> Bool {
        isSwitching && candidate == session
    }
}
