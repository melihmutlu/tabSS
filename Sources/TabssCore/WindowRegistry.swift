/// Recency bookkeeping for switchable windows and their apps. The app layer feeds it Accessibility events;
/// this type only decides order and focus.
public struct WindowRegistry<Window: Hashable & Sendable, App: Hashable & Sendable>: Sendable {
    public private(set) var focusedWindow: Window?
    private var windowRecency: MRUList<Window>
    private var appRecency = MRUList<App>()
    private var owners: [Window: App] = [:]

    /// `zOrder` (frontmost first) seeds window recency until real focus changes are observed.
    public init(zOrder: [Window] = []) {
        windowRecency = MRUList(zOrder)
    }

    public func owner(of window: Window) -> App? {
        owners[window]
    }

    public func windows(of app: App) -> [Window] {
        owners.filter { $0.value == app }.map(\.key)
    }

    /// Keeps the seeded position if the window was in the initial z-order, otherwise ranks it last.
    @discardableResult
    public mutating func add(_ window: Window, of app: App) -> Bool {
        guard owners[window] == nil else { return false }
        owners[window] = app
        windowRecency.appendIfAbsent(window)
        return true
    }

    public mutating func remove(_ window: Window) {
        guard owners.removeValue(forKey: window) != nil else { return }
        windowRecency.remove(window)
        if focusedWindow == window { focusedWindow = nil }
    }

    /// Returns the windows that were removed with the app.
    public mutating func removeApp(_ app: App) -> [Window] {
        let removed = windows(of: app)
        removed.forEach { remove($0) }
        appRecency.remove(app)
        return removed
    }

    /// Returns the window that just lost focus, if any. Unknown windows count as "no switchable window focused".
    @discardableResult
    public mutating func focus(_ window: Window?) -> Window? {
        let window = window.flatMap { owners[$0] == nil ? nil : $0 }
        guard window != focusedWindow else { return nil }
        let previous = focusedWindow
        focusedWindow = window
        if let window { windowRecency.touch(window) }
        return previous
    }

    /// Returns the window that just lost focus, if any.
    @discardableResult
    public mutating func activate(_ app: App, focusedWindow window: Window?) -> Window? {
        appRecency.touch(app)
        return focus(window)
    }

    /// Windows by recency, then the running apps that have none, by recency.
    public func items(runningApps: [App]) -> [SwitcherItem<Window, App>] {
        let appsWithWindows = Set(owners.values)
        return SwitcherOrdering.items(
            windowsByRecency: windowRecency.elements.filter { owners[$0] != nil },
            windowlessApps: runningApps.filter { !appsWithWindows.contains($0) },
            appRecency: appRecency.elements
        )
    }
}
