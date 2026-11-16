import ApplicationServices
import TabssCore

/// A window found by discovery, already checked to be a switchable window of the expected app.
struct DiscoveredWindow: @unchecked Sendable {  // AXUIElement is an immutable, thread-safe CF object
    let element: AXUIElement
    let id: CGWindowID
}

/// Finds an app's windows on every Space, not just the current one.
enum WindowDiscovery {
    // Window element IDs are small in practice; this is the range AltTab has used reliably for years.
    private static let elementIDs: Range<UInt64> = 0..<1000
    private static let timeBudget: Duration = .milliseconds(100)
    private static let maxResults = 64

    /// `isComplete` is false when the scan was cut short and is worth repeating later.
    /// Slow (one Accessibility round trip per candidate), so call it off the main thread.
    static func windows(of pid: pid_t, excluding known: Set<CGWindowID>, appIsHidden: Bool) -> (windows: [DiscoveredWindow], isComplete: Bool) {
        let clock = ContinuousClock()
        let deadline = clock.now + timeBudget
        var found: [DiscoveredWindow] = []
        var seen = known
        for elementID in elementIDs {
            guard found.count < maxResults, clock.now < deadline else { return (found, false) }
            guard let element = PrivateAPI.element(pid: pid, elementID: elementID) else { continue }
            let subrole = AX.string(element, kAXSubroleAttribute)
            guard subrole == WindowEligibility.standardSubrole || subrole == WindowEligibility.dialogSubrole,
                  let id = PrivateAPI.windowID(of: element), seen.insert(id).inserted,
                  let facts = WindowServer.facts(for: id), facts.ownerPID == pid,
                  WindowEligibility.isSwitchable(subrole: subrole, layer: facts.layer, size: facts.bounds.size),
                  !isGhost(id, element: element, appIsHidden: appIsHidden)
            else { continue }
            found.append(DiscoveredWindow(element: element, id: id))
        }
        return (found, true)
    }

    /// Background tabs, and windows an app hid instead of closing, belong to no Space and aren't switchable.
    /// Minimized windows and hidden apps' windows legitimately belong to none, so they are asked about live;
    /// an app that doesn't answer gets the benefit of the doubt.
    static func isGhost(_ id: CGWindowID, element: AXUIElement, appIsHidden: Bool) -> Bool {
        !appIsHidden && PrivateAPI.isOnAnySpace(id) == false && AX.bool(element, kAXMinimizedAttribute) == false
    }
}
