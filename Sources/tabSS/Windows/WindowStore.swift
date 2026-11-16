import AppKit
import ApplicationServices
import TabssCore

struct WindowInfo {
    let id: CGWindowID
    let app: NSRunningApplication
    let element: AXUIElement
    var title: String
    var isMinimized: Bool
}

@MainActor
protocol WindowStoreObserver: AnyObject {
    func windowStore(_ store: WindowStore, didAdd window: WindowInfo)
    func windowStore(_ store: WindowStore, didRemove id: CGWindowID)
    /// The window was focused until now; it may already be minimizing, hiding or on another Space.
    func windowStore(_ store: WindowStore, focusDidLeave window: WindowInfo)
}

/// Every switchable window and app, kept current by Accessibility and workspace notifications,
/// so opening the switcher only reads memory.
@MainActor
final class WindowStore {
    private(set) var windows: [CGWindowID: WindowInfo] = [:]
    weak var observer: WindowStoreObserver?

    private var registry = WindowRegistry<CGWindowID, pid_t>()
    private var watchers: [pid_t: AppWatcher] = [:]
    // Skipped by bulk refreshes until they show signs of life (an event or an activation).
    private var unresponsiveApps: Set<pid_t> = []
    private var appsAwaitingAttachRetry: Set<pid_t> = []
    // Apps whose windows on other Spaces haven't been fully scanned yet, and scans in flight.
    private var appsNeedingDiscovery: Set<pid_t> = []
    private var appsBeingDiscovered: Set<pid_t> = []
    private var pendingRechecks = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private let discoveryQueue = DispatchQueue(label: "tabSS.discovery", qos: .utility)

    private static let messagingTimeout: Float = 0.25
    private static let maxTitleScalars = 512
    private static let attachRetryDelays: [Duration] = [.milliseconds(250), .milliseconds(750), .seconds(2)]
    // A window often reports its final subrole, size and Space only a while after it is created.
    private static let newWindowRecheckDelays: [Duration] = [.milliseconds(500), .seconds(2)]
    // Bounds the work an app spamming window-created notifications can cause.
    private static let maxPendingRechecks = 32
    private static let refreshBudgetPerApp: Duration = .milliseconds(500)

    var focusedWindowID: CGWindowID? { registry.focusedWindow }

    func start() {
        AX.limitMessagingTimeout(to: Self.messagingTimeout)
        registry = WindowRegistry(zOrder: WindowServer.onScreenWindowIDsFrontToBack())
        NSWorkspace.shared.runningApplications.forEach { attach($0) }
        refreshWindows(of: Array(watchers.values))
        watchers.values.forEach(discoverWindowsOnOtherSpaces)
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            syncActivation(of: frontmost)
        }
        observeWorkspace()
    }

    func orderedItems() -> [SwitcherItem<CGWindowID, pid_t>] {
        let runningApps = NSWorkspace.shared.runningApplications.filter(isSwitchable).map(\.processIdentifier)
        return registry.items(runningApps: runningApps)
    }

    // MARK: - Apps

    private func isSwitchable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    /// Creates the app's watcher if it has none yet; the caller refreshes its windows.
    /// Returns whether a new watcher was attached.
    @discardableResult
    private func attach(_ app: NSRunningApplication, retry: Int = 0) -> Bool {
        let pid = app.processIdentifier
        guard isSwitchable(app), watchers[pid] == nil else { return false }
        guard let watcher = AppWatcher(app: app, onEvent: { [weak self] watcher, event in self?.handle(event, from: watcher) }) else {
            scheduleAttachRetry(app, retry: retry)
            return false
        }
        watchers[pid] = watcher
        unresponsiveApps.remove(pid)
        appsNeedingDiscovery.insert(pid)
        return true
    }

    private func scheduleAttachRetry(_ app: NSRunningApplication, retry: Int) {
        let pid = app.processIdentifier
        guard retry < Self.attachRetryDelays.count, appsAwaitingAttachRetry.insert(pid).inserted else { return }
        let delay = Self.attachRetryDelays[retry]
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            appsAwaitingAttachRetry.remove(pid)
            if attachAndRefresh(app, retry: retry + 1), app.isActive {
                syncActivation(of: app)
            }
        }
    }

    @discardableResult
    private func attachAndRefresh(_ app: NSRunningApplication, retry: Int = 0) -> Bool {
        guard attach(app, retry: retry), let watcher = watchers[app.processIdentifier] else { return false }
        refreshWindows(of: [watcher])
        discoverWindowsOnOtherSpaces(of: watcher)
        return true
    }

    /// Accessibility lists only the current Space's windows; the rest are found the slow way, off the main thread.
    /// Repeated (on activation or recovery) until one scan has completed.
    private func discoverWindowsOnOtherSpaces(of watcher: AppWatcher) {
        let pid = watcher.app.processIdentifier
        guard appsNeedingDiscovery.contains(pid), !unresponsiveApps.contains(pid),
              appsBeingDiscovered.insert(pid).inserted
        else { return }
        let known = Set(registry.windows(of: pid))
        let appIsHidden = watcher.app.isHidden
        discoveryQueue.async { [weak self] in
            let result = WindowDiscovery.windows(of: pid, excluding: known, appIsHidden: appIsHidden)
            DispatchQueue.main.async {
                guard let self else { return }
                self.appsBeingDiscovered.remove(pid)
                guard let watcher = self.watchers[pid], !self.unresponsiveApps.contains(pid) else { return }
                let addedAll = self.addWithinBudget(result.windows.map { ($0.element, $0.id) }, of: watcher)
                if result.isComplete && addedAll { self.appsNeedingDiscovery.remove(pid) }
            }
        }
    }

    private func detach(_ pid: pid_t) {
        watchers[pid] = nil
        unresponsiveApps.remove(pid)
        appsNeedingDiscovery.remove(pid)
        registry.removeApp(pid).forEach(forget)
    }

    /// Adds windows Accessibility currently lists and drops ones the window server no longer knows,
    /// which covers destroy notifications that were never delivered.
    private func refreshWindows(of targets: [AppWatcher]) {
        for watcher in targets {
            let pid = watcher.app.processIdentifier
            guard let elements = AX.elements(watcher.element, kAXWindowsAttribute) else {
                unresponsiveApps.insert(pid)
                continue
            }
            unresponsiveApps.remove(pid)
            addWithinBudget(elements.map { ($0, nil) }, of: watcher)
        }
        // Taken after listing, so windows created meanwhile aren't pruned; nil on a window server hiccup.
        guard let existing = WindowServer.allWindowIDs() else { return }
        for watcher in targets {
            let pid = watcher.app.processIdentifier
            let gone = registry.windows(of: pid).filter { !existing.contains($0) }
            gone.forEach(removeWindow)
            // Telling ghosts apart asks the app about each window, so skip apps that aren't answering.
            guard !unresponsiveApps.contains(pid) else { continue }
            withinBudget(registry.windows(of: pid), for: pid, removeGhost)
        }
    }

    /// Returns false if the app was too slow to add them all.
    @discardableResult
    private func addWithinBudget(_ candidates: [(element: AXUIElement, id: CGWindowID?)], of watcher: AppWatcher) -> Bool {
        withinBudget(candidates, for: watcher.app.processIdentifier) { addWindow($0.element, of: watcher, id: $0.id) }
    }

    /// Each item costs calls into the app; a slow app gets cut off and treated as unresponsive.
    /// Returns false if it was cut off.
    @discardableResult
    private func withinBudget<Item>(_ items: [Item], for pid: pid_t, _ work: (Item) -> Void) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.refreshBudgetPerApp
        for item in items {
            guard clock.now < deadline else {
                unresponsiveApps.insert(pid)
                return false
            }
            work(item)
        }
        return true
    }

    /// A window that turned into a background tab, or that its app hid instead of closing, is no longer switchable.
    private func removeGhost(_ id: CGWindowID) {
        guard let window = windows[id],
              WindowDiscovery.isGhost(id, element: window.element, appIsHidden: window.app.isHidden)
        else { return }
        removeWindow(id)
    }

    /// Records `app` as the most recent and focuses its focused window. Non-regular apps, and apps
    /// Accessibility can't reach, leave no switchable window focused.
    private func syncActivation(of app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard isSwitchable(app) else {
            reportFocusLeft(registry.focus(nil))
            return
        }
        // Asking a hung app for its focused window would cost another timeout.
        guard let watcher = watchers[pid], !unresponsiveApps.contains(pid) else {
            reportFocusLeft(registry.activate(pid, focusedWindow: nil))
            return
        }
        let focused = AX.element(watcher.element, kAXFocusedWindowAttribute).flatMap { addWindow($0, of: watcher) }
        reportFocusLeft(registry.activate(pid, focusedWindow: focused))
    }

    // MARK: - Windows

    /// `id`, when already resolved (by discovery), saves a round trip into the app.
    @discardableResult
    private func addWindow(_ element: AXUIElement, of watcher: AppWatcher, id knownWindowID: CGWindowID? = nil) -> CGWindowID? {
        if let known = knownID(of: element) { return known }
        let pid = watcher.app.processIdentifier
        guard let id = knownWindowID ?? PrivateAPI.windowID(of: element) else { return nil }
        // The ID comes from the app itself; it must not claim another app's window.
        if let owner = registry.owner(of: id) { return owner == pid ? id : nil }
        guard let facts = WindowServer.facts(for: id),
              facts.ownerPID == pid,
              WindowEligibility.isSwitchable(subrole: AX.string(element, kAXSubroleAttribute), layer: facts.layer, size: facts.bounds.size)
        else { return nil }
        guard !WindowDiscovery.isGhost(id, element: element, appIsHidden: watcher.app.isHidden) else { return nil }

        registry.add(id, of: pid)
        let window = WindowInfo(
            id: id,
            app: watcher.app,
            element: element,
            title: title(of: element),
            isMinimized: AX.bool(element, kAXMinimizedAttribute) ?? false
        )
        windows[id] = window
        watcher.watch(window: element)
        observer?.windowStore(self, didAdd: window)
        return id
    }

    private func removeWindow(_ id: CGWindowID) {
        registry.remove(id)
        forget(id)
    }

    private func forget(_ id: CGWindowID) {
        guard windows.removeValue(forKey: id) != nil else { return }
        observer?.windowStore(self, didRemove: id)
    }

    private func reportFocusLeft(_ id: CGWindowID?) {
        guard let id, let window = windows[id] else { return }
        observer?.windowStore(self, focusDidLeave: window)
    }

    /// Matching in memory first avoids a round trip into the app, and works for destroyed windows.
    private func knownID(of element: AXUIElement) -> CGWindowID? {
        windows.values.first { CFEqual($0.element, element) }?.id
    }

    private func title(of element: AXUIElement) -> String {
        let scalars = (AX.string(element, kAXTitleAttribute) ?? "").unicodeScalars.prefix(Self.maxTitleScalars)
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - Events

    private func handle(_ event: AppWatcher.Event, from watcher: AppWatcher) {
        if unresponsiveApps.remove(watcher.app.processIdentifier) != nil {
            discoverWindowsOnOtherSpaces(of: watcher)  // it may have been skipped while the app was busy
        }
        switch event {
        case let .windowCreated(element):
            if addWindow(element, of: watcher) == nil {
                recheckLater(element, of: watcher)
            }
        case let .focusedWindowChanged(element):
            guard watcher.app.isActive else { return }
            let previous = registry.focus(addWindow(element, of: watcher))
            reportFocusLeft(previous)
            if let previous { removeGhost(previous) }  // switching tabs sends the previous tab to the background
        case let .windowDestroyed(element):
            if let id = knownID(of: element) { removeWindow(id) }
        case let .windowMinimizedChanged(element, isMinimized):
            if let id = knownID(of: element) { windows[id]?.isMinimized = isMinimized }
        case let .windowTitleChanged(element):
            if let id = knownID(of: element) { windows[id]?.title = title(of: element) }
        }
    }

    private func recheckLater(_ element: AXUIElement, of watcher: AppWatcher, attempt: Int = 0) {
        guard attempt < Self.newWindowRecheckDelays.count, pendingRechecks < Self.maxPendingRechecks else { return }
        pendingRechecks += 1
        let delay = Self.newWindowRecheckDelays[attempt]
        nonisolated(unsafe) let element = element  // only used back on the main actor
        Task { [weak self, weak watcher] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            pendingRechecks -= 1
            guard let watcher, watchers[watcher.app.processIdentifier] === watcher else { return }
            guard addWindow(element, of: watcher) != nil else {
                recheckLater(element, of: watcher, attempt: attempt + 1)
                return
            }
            // Its focus change arrived while it wasn't switchable yet.
            if watcher.app.isActive { syncActivation(of: watcher.app) }
        }
    }

    private func appDidActivate(_ app: NSRunningApplication) {
        // Attaching late covers apps that weren't ready at launch or became regular apps afterwards.
        if !attachAndRefresh(app), let watcher = watchers[app.processIdentifier] {
            refreshWindows(of: [watcher])
            discoverWindowsOnOtherSpaces(of: watcher)
        }
        syncActivation(of: app)
    }

    private func activeSpaceDidChange() {
        // Accessibility lists only the current Space's windows, so pick up any we haven't seen yet.
        // Unresponsive apps would cost a timeout each; they catch up when they next activate or send an event.
        refreshWindows(of: watchers.values.filter { !unresponsiveApps.contains($0.app.processIdentifier) })
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (WindowStore, NSRunningApplication?) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self, app)
                }
            }
            workspaceObservers.append(token)
        }
        observe(NSWorkspace.didLaunchApplicationNotification) { store, app in
            // Windows restored during launch existed before the watcher, so list them now.
            if let app { store.attachAndRefresh(app) }
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { store, app in
            if let app { store.detach(app.processIdentifier) }
        }
        observe(NSWorkspace.didActivateApplicationNotification) { store, app in
            if let app { store.appDidActivate(app) }
        }
        observe(NSWorkspace.didUnhideApplicationNotification) { store, app in
            // Background tabs can't be told apart while their app is hidden; prune them now.
            if let app, let watcher = store.watchers[app.processIdentifier] { store.refreshWindows(of: [watcher]) }
        }
        observe(NSWorkspace.activeSpaceDidChangeNotification) { store, _ in store.activeSpaceDidChange() }
    }
}
