import AppKit
import ApplicationServices
import OSLog
import TabssCore

struct WindowInfo {
    let id: CGWindowID
    let app: NSRunningApplication
    let element: AXUIElement
    var title: String
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
    private let logger = Logger(subsystem: "local.tabss", category: "Windows")
    private(set) var windows: [CGWindowID: WindowInfo] = [:]
    /// Running regular apps by pid, kept from workspace notifications: asking NSRunningApplication for
    /// properties can be a round trip to LaunchServices per app, too slow for every Cmd+Tab.
    private(set) var apps: [pid_t: NSRunningApplication] = [:]
    weak var observer: WindowStoreObserver?

    private var registry = WindowRegistry<CGWindowID, pid_t>()
    private var watchers: [pid_t: AppWatcher] = [:]
    // Apps that answered too slowly, and since when. tabSS stops calling into them for a cooldown,
    // or until the user activates them again.
    private var unresponsiveSince: [pid_t: ContinuousClock.Instant] = [:]
    private var mainThreadTime: [pid_t: UsageBudget] = [:]
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
    // Main-thread time any one app may cost (events, refreshes, rechecks together) before it is cut off.
    private static let mainThreadTimePerApp: Duration = .milliseconds(500)
    private static let mainThreadTimeWindow: Duration = .seconds(1)
    // Bounds what a hostile app can cost to the budget once per cooldown (~5% of the main thread).
    private static let unresponsiveCooldown: Duration = .seconds(10)

    var focusedWindowID: CGWindowID? { registry.focusedWindow }

    func start() {
        AX.limitMessagingTimeout(to: Self.messagingTimeout)
        registry = WindowRegistry(zOrder: WindowServer.onScreenWindowIDsFrontToBack())
        observeWorkspace()
        Task { await attachRunningApps() }
    }

    /// Records a switch tabSS made right away, so a quick second switch sees the new order
    /// even before macOS reports the focus change.
    func noteSwitch(to entry: SwitcherItem<CGWindowID, pid_t>) {
        switch entry {
        case let .window(id):
            guard let window = windows[id] else { return }
            reportFocusLeft(registry.activate(window.app.processIdentifier, focusedWindow: id))
        case let .app(pid):
            reportFocusLeft(registry.activate(pid, focusedWindow: nil))
        }
    }

    /// One app per main-actor turn: at login many apps are busy, and Cmd+Tab must still get through in between.
    private func attachRunningApps() async {
        for app in NSWorkspace.shared.runningApplications {
            noteRunning(app)
        }
        // The frontmost app first, so Cmd+Tab works for what the user is looking at right away.
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            attachAndRefresh(frontmost)
            syncActivation(of: frontmost)
        }
        for app in NSWorkspace.shared.runningApplications {
            await Task.yield()
            attachAndRefresh(app)
        }
    }

    func orderedItems() -> [SwitcherItem<CGWindowID, pid_t>] {
        // A quit notification can be missed; a process that no longer exists must never be offered.
        for pid in Set(apps.keys).union(watchers.keys) where !Self.processExists(pid) {
            detach(pid)
        }
        return registry.items(runningApps: apps.keys.sorted())
    }

    private static func processExists(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Keeps `apps` current; an app's activation policy can change after launch, so this runs on activation too.
    private func noteRunning(_ app: NSRunningApplication) {
        apps[app.processIdentifier] = isSwitchable(app) ? app : nil
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
        unresponsiveSince[pid] = nil
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
        guard appsNeedingDiscovery.contains(pid), !isUnresponsive(pid),
              appsBeingDiscovered.insert(pid).inserted
        else { return }
        let known = Set(registry.windows(of: pid))
        let appIsHidden = watcher.app.isHidden
        discoveryQueue.async { [weak self] in
            let result = WindowDiscovery.windows(of: pid, excluding: known, appIsHidden: appIsHidden)
            DispatchQueue.main.async {
                guard let self else { return }
                self.appsBeingDiscovered.remove(pid)
                guard let watcher = self.watchers[pid], !self.isUnresponsive(pid) else { return }
                let addedAll = self.addEach(result.windows.map { ($0.element, $0.id) }, of: watcher)
                if result.isComplete && addedAll { self.appsNeedingDiscovery.remove(pid) }
            }
        }
    }

    private func detach(_ pid: pid_t) {
        apps[pid] = nil
        watchers[pid] = nil
        unresponsiveSince[pid] = nil
        appsNeedingDiscovery.remove(pid)
        registry.removeApp(pid).forEach(forget)
    }

    /// Adds windows Accessibility currently lists and drops ones the window server no longer knows,
    /// which covers destroy notifications that were never delivered.
    private func refreshWindows(of targets: [AppWatcher]) {
        for watcher in targets {
            let pid = watcher.app.processIdentifier
            var listed: [AXUIElement]?
            guard callingApp(pid, { listed = AX.elements(watcher.element, kAXWindowsAttribute) }) else { continue }
            guard let elements = listed else {
                markUnresponsive(pid)  // timed out
                continue
            }
            addEach(elements.map { ($0, nil) }, of: watcher)
        }
        // Taken after listing, so windows created meanwhile aren't pruned; nil on a window server hiccup.
        guard let existing = WindowServer.allWindowIDs() else { return }
        for watcher in targets {
            let pid = watcher.app.processIdentifier
            for id in registry.windows(of: pid) {
                if !existing.contains(id) {
                    removeWindow(id, reason: "unknown to the window server")
                } else if !callingApp(pid, { removeGhost(id) }) {
                    break
                }
            }
        }
    }

    /// Returns false if the app was cut off before all were added.
    @discardableResult
    private func addEach(_ candidates: [(element: AXUIElement, id: CGWindowID?)], of watcher: AppWatcher) -> Bool {
        candidates.allSatisfy { candidate in
            callingApp(watcher.app.processIdentifier) { addWindow(candidate.element, of: watcher, id: candidate.id) }
        }
    }

    /// Runs `work`, which calls into the app, unless the app is marked unresponsive; returns whether it ran.
    /// The time it takes is charged to the app, so neither one slow call nor many quick ones can monopolize
    /// the main thread (and with it the switcher).
    @discardableResult
    private func callingApp(_ pid: pid_t, _ work: () -> Void) -> Bool {
        guard !isUnresponsive(pid) else { return false }
        let clock = ContinuousClock()
        let started = clock.now
        work()
        let now = clock.now
        var budget = mainThreadTime[pid] ?? UsageBudget(limit: Self.mainThreadTimePerApp, per: Self.mainThreadTimeWindow)
        if budget.charge(now - started, at: now) { markUnresponsive(pid) }
        mainThreadTime[pid] = budget
        return true
    }

    /// A window that turned into a background tab, or that its app hid instead of closing, is no longer switchable.
    private func removeGhost(_ id: CGWindowID) {
        guard let window = windows[id],
              WindowDiscovery.isGhost(id, element: window.element, appIsHidden: window.app.isHidden)
        else { return }
        removeWindow(id, reason: "no Space")
    }

    private func markUnresponsive(_ pid: pid_t) {
        logger.debug("app \(pid) marked unresponsive")
        unresponsiveSince[pid] = .now
    }

    private func isUnresponsive(_ pid: pid_t) -> Bool {
        guard let since = unresponsiveSince[pid] else { return false }
        guard ContinuousClock.now - since < Self.unresponsiveCooldown else {
            unresponsiveSince[pid] = nil
            return false
        }
        return true
    }

    /// Records `app` as the most recent and focuses its focused window. Non-regular apps, and apps
    /// Accessibility can't reach, leave no switchable window focused.
    private func syncActivation(of app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard isSwitchable(app) else {
            reportFocusLeft(registry.focus(nil))
            return
        }
        var focused: CGWindowID?
        var answered = false
        if let watcher = watchers[pid] {
            callingApp(pid) {
                let reply = AX.elementReply(watcher.element, kAXFocusedWindowAttribute)
                answered = reply.answered
                focused = reply.element.flatMap { addWindow($0, of: watcher) }
            }
        }
        // "No focused window" is a real answer (e.g. Finder after clicking the desktop); only silence gets a stand-in.
        let standIn = answered ? nil : frontmostKnownWindow(of: pid)
        reportFocusLeft(registry.activate(pid, focusedWindow: focused ?? standIn))
    }

    /// When an app doesn't say which window is focused in time (Electron apps often don't), its frontmost
    /// window in the window server's stacking order is the best stand-in, and costs no call into the app.
    private func frontmostKnownWindow(of pid: pid_t) -> CGWindowID? {
        WindowServer.onScreenWindowIDsFrontToBack().first { registry.owner(of: $0) == pid }
    }

    // MARK: - Windows

    /// `id`, when already resolved (by discovery), saves a round trip into the app.
    @discardableResult
    private func addWindow(_ element: AXUIElement, of watcher: AppWatcher, id knownWindowID: CGWindowID? = nil) -> CGWindowID? {
        if let known = knownID(of: element, in: watcher.app.processIdentifier) { return known }
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
            title: title(of: element)
        )
        windows[id] = window
        watcher.watch(window: element)
        observer?.windowStore(self, didAdd: window)
        return id
    }

    private func removeWindow(_ id: CGWindowID, reason: StaticString) {
        logger.debug("remove \(id): \(reason, privacy: .public)")
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
    private func knownID(of element: AXUIElement, in pid: pid_t) -> CGWindowID? {
        registry.windows(of: pid).first { windows[$0].map { CFEqual($0.element, element) } ?? false }
    }

    private func title(of element: AXUIElement) -> String {
        let scalars = (AX.string(element, kAXTitleAttribute) ?? "").unicodeScalars.prefix(Self.maxTitleScalars)
        return String(String.UnicodeScalarView(scalars))
    }

    // MARK: - Events

    /// Events from an unresponsive app are still handled from memory, just without calling back into it.
    private func handle(_ event: AppWatcher.Event, from watcher: AppWatcher) {
        let pid = watcher.app.processIdentifier
        switch event {
        case let .windowCreated(element):
            var added: CGWindowID?
            if callingApp(pid, { added = addWindow(element, of: watcher) }), added == nil {
                recheckLater(element, of: watcher)
            }
        case let .focusedWindowChanged(element):
            guard watcher.app.isActive else { return }
            var focused = knownID(of: element, in: pid)
            if focused == nil {
                callingApp(pid) { focused = addWindow(element, of: watcher) }
            }
            let previous = registry.focus(focused)
            reportFocusLeft(previous)
            if let previous {
                callingApp(pid) { removeGhost(previous) }  // switching tabs sends the previous tab to the background
            }
        case let .windowDestroyed(element):
            if let id = knownID(of: element, in: pid) { removeWindow(id, reason: "destroyed") }
        case let .windowTitleChanged(element):
            if let id = knownID(of: element, in: pid) {
                callingApp(pid) { windows[id]?.title = title(of: element) }
            }
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
            var added: CGWindowID?
            guard callingApp(watcher.app.processIdentifier, { added = addWindow(element, of: watcher) }) else { return }
            guard added != nil else {
                recheckLater(element, of: watcher, attempt: attempt + 1)
                return
            }
            // Its focus change arrived while it wasn't switchable yet.
            if watcher.app.isActive { syncActivation(of: watcher.app) }
        }
    }

    private func appDidActivate(_ app: NSRunningApplication) {
        noteRunning(app)
        // The user chose this app, so it gets another chance even if it was slow before.
        unresponsiveSince[app.processIdentifier] = nil
        // Attaching late covers apps that weren't ready at launch or became regular apps afterwards.
        if !attachAndRefresh(app), let watcher = watchers[app.processIdentifier] {
            refreshWindows(of: [watcher])
            discoverWindowsOnOtherSpaces(of: watcher)
        }
        syncActivation(of: app)
    }

    private func activeSpaceDidChange() {
        // Accessibility lists only the current Space's windows, so pick up any we haven't seen yet.
        refreshWindows(of: Array(watchers.values))
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
            guard let app else { return }
            // A reused pid still held by an app whose quit went unnoticed: start over for the new one.
            if let stale = store.watchers[app.processIdentifier], stale.app != app {
                store.detach(app.processIdentifier)
            }
            store.noteRunning(app)
            store.attachAndRefresh(app)
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
