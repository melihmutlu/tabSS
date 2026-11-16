import CoreGraphics
import Foundation
import os
import TabssCore

/// System-wide keyboard hook. It runs on its own thread so a busy main thread never delays anyone's typing;
/// routing happens there and the resulting actions are delivered to the main actor in order.
final class HotkeyMonitor: Sendable {
    /// `issuedAt` is when the tap routed the action, so late deliveries to a blocked main thread can be spotted.
    typealias ActionHandler = @MainActor (_ action: KeyAction, _ session: Int, _ issuedAt: ContinuousClock.Instant) -> Void

    private let onAction: ActionHandler
    private let state = OSAllocatedUnfairLock(initialState: HotkeyState())
    // Written once on the main actor before the tap thread starts; read-only afterwards.
    nonisolated(unsafe) private var tap: CFMachPort?

    init(onAction: @escaping ActionHandler) {
        self.onAction = onAction
    }

    /// Fails when Accessibility access is missing. The monitor then lives as long as the tap, i.e. the app.
    @MainActor
    func start() -> Bool {
        guard tap == nil else { return true }
        let retainedSelf = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: TapEvent.keyboardEventMask,
            callback: hotkeyTapCallback,
            userInfo: retainedSelf.toOpaque()
        ) else {
            retainedSelf.release()
            return false
        }
        self.tap = tap

        let thread = Thread { [self] in runTapLoop() }
        thread.name = "tabSS.hotkeys"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func isOpen(_ session: Int) -> Bool {
        state.withLock { $0.isOpen(session) }
    }

    /// The main actor finished `session` on its own, e.g. by a click or because there was nothing to show.
    func sessionEnded(_ session: Int) {
        state.withLock { $0.end(session) }
    }

    private func runTapLoop() {
        guard let tap else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    /// Runs on the tap thread. Returns whether the event should be swallowed.
    fileprivate func handle(_ event: TapEvent) -> Bool {
        switch event {
        case .tapDisabled:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            let isCommandHeld = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
            if let routed = state.withLock({ $0.eventsMayHaveBeenLost(isCommandHeld: isCommandHeld) }) {
                deliver(routed)
            }
            return false
        case let .input(input):
            let routed = state.withLock { $0.route(input) }
            deliver(routed)
            return routed.decision.consumesEvent
        }
    }

    private func deliver(_ routed: HotkeyState.Routed) {
        guard let action = routed.decision.action else { return }
        let onAction = onAction
        let issuedAt = ContinuousClock.now
        DispatchQueue.main.async { onAction(action, routed.session, issuedAt) }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passThrough = Unmanaged.passUnretained(event)
    guard let userInfo, let tapEvent = TapEvent(type: type, event: event) else { return passThrough }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(tapEvent) ? nil : passThrough
}
