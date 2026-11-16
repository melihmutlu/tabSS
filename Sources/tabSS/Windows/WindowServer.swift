import CoreGraphics
import Foundation

/// Read-only window facts from the window server, keyed by window ID.
enum WindowServer {
    struct WindowFacts {
        let ownerPID: pid_t
        let layer: Int
        let bounds: CGRect
        let isOnScreen: Bool
    }

    static func facts(for id: CGWindowID) -> WindowFacts? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[CFString: Any]])?.first,
              let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
              let layer = info[kCGWindowLayer] as? Int,
              let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else { return nil }
        return WindowFacts(ownerPID: ownerPID, layer: layer, bounds: bounds, isOnScreen: info[kCGWindowIsOnscreen] as? Bool ?? false)
    }

    /// Every window the window server knows, on any Space, including minimized ones. Nil if it can't say.
    static func allWindowIDs() -> Set<CGWindowID>? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[CFString: Any]] else { return nil }
        return Set(list.compactMap { $0[kCGWindowNumber] as? CGWindowID })
    }

    /// On-screen windows, frontmost first: the best available guess at recency when tabSS starts.
    static func onScreenWindowIDsFrontToBack() -> [CGWindowID] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]]
        return list?.compactMap { $0[kCGWindowNumber] as? CGWindowID } ?? []
    }
}
