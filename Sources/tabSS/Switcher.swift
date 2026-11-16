import AppKit
import TabssCore

/// One switcher item: a window, or a running app that has no windows.
enum SwitcherEntry {
    case window(WindowInfo)
    case app(NSRunningApplication)

    var app: NSRunningApplication {
        switch self {
        case let .window(window): window.app
        case let .app(app): app
        }
    }
}

/// Wires the keyboard hook, window store, thumbnails, panel and activation into one switcher.
@MainActor
final class Switcher {
    // An action the main thread receives this late (it was blocked) no longer reflects what the user sees.
    private static let maxActionDelay: Duration = .seconds(1)

    private let store = WindowStore()
    private let thumbnails: ThumbnailCache
    private let activator = WindowActivator()
    private let panel = SwitcherPanel()
    private var monitor: HotkeyMonitor?
    private var screen: NSScreen?

    private lazy var controller = SwitcherController<SwitcherEntry>(dependencies: .init(
        snapshot: { [unowned self] in snapshot() },
        show: { [unowned self] entries, index in show(entries, selectedIndex: index) },
        select: { [unowned self] in panel.select($0) },
        hide: { [unowned self] in panel.hide() },
        activate: { [unowned self] in activate($0) },
        sessionEnded: { [unowned self] in monitor?.sessionEnded($0) },
        commandKeyState: { [unowned self] in commandKeyState(session: $0) },
        schedule: Self.schedule
    ))

    init() {
        thumbnails = ThumbnailCache(store: store)
    }

    /// Fails when the keyboard hook can't be installed (Accessibility not granted).
    func start() -> Bool {
        let monitor = HotkeyMonitor { [weak self] action, session, issuedAt in
            self?.handle(action, session: session, issuedAt: issuedAt)
        }
        guard monitor.start() else { return false }
        self.monitor = monitor
        panel.onHover = { [weak self] in self?.controller.pointerHovered(at: $0) }
        panel.onClick = { [weak self] in self?.controller.pointerClicked(at: $0) }
        store.start()
        return true
    }

    private func handle(_ action: KeyAction, session: Int, issuedAt: ContinuousClock.Instant) {
        guard ContinuousClock.now - issuedAt <= Self.maxActionDelay else {
            // Don't switch windows long after the fact; just close the session.
            controller.handle(.command(.cancel), session: session)
            monitor?.sessionEnded(session)
            return
        }
        controller.handle(action, session: session)
    }

    private func snapshot() -> SwitcherController<SwitcherEntry>.Snapshot {
        let screen = targetScreen()
        self.screen = screen
        let focused = store.focusedWindowID
        if let focused {
            thumbnails.capture(focused)  // it is about to lose focus and is still on screen
        }
        let entries = store.orderedItems().prefix(screen.map(panel.capacity) ?? 0).compactMap(entry)
        var firstItemIsFocused = false
        if case let .window(first)? = entries.first { firstItemIsFocused = first.id == focused }
        let columns = screen.map { panel.columns(forItemCount: entries.count, on: $0) }
        return .init(entries: entries, firstItemIsFocused: firstItemIsFocused, columns: columns)
    }

    private func entry(for item: SwitcherItem<CGWindowID, pid_t>) -> SwitcherEntry? {
        switch item {
        case let .window(id): store.windows[id].map(SwitcherEntry.window)
        case let .app(pid): store.apps[pid].map(SwitcherEntry.app)
        }
    }

    private func show(_ entries: [SwitcherEntry], selectedIndex: Int) {
        thumbnails.discardIfPermissionRevoked()
        let tiles = entries.map { entry -> TileContent in
            let appName = DisplayText.title(entry.app.localizedName ?? "", fallback: "")
            switch entry {
            case let .window(window):
                let title = DisplayText.title(window.title, fallback: appName)
                return TileContent(title: title, appName: appName, icon: entry.app.icon, thumbnail: thumbnails.image(for: window.id))
            case .app:
                return TileContent(title: appName, appName: appName, icon: entry.app.icon, thumbnail: nil)
            }
        }
        guard let screen = screen ?? targetScreen() else { return }
        panel.show(tiles, selectedIndex: selectedIndex, on: screen)
    }

    private func activate(_ entry: SwitcherEntry) {
        switch entry {
        case let .window(window):
            store.noteSwitch(to: .window(window.id))
            activator.activate(window)
        case let .app(app):
            store.noteSwitch(to: .app(app.processIdentifier))
            activator.activate(app)
        }
    }

    nonisolated private static func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: delay)
            await action()
        }
    }

    private func commandKeyState(session: Int) -> CommandKeyState {
        guard monitor?.isOpen(session) == true else { return .releaseSeen }
        return CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) ? .held : .releaseMissed
    }

    /// The display showing the focused window, else the one under the pointer. Nil with no display attached.
    private func targetScreen() -> NSScreen? {
        if let id = store.focusedWindowID, let bounds = WindowServer.facts(for: id)?.bounds,
           let screen = NSScreen.containing(windowServerRect: bounds) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}

private extension NSScreen {
    /// Window server rects have a top-left origin on the primary display; AppKit's are bottom-left.
    static func containing(windowServerRect rect: CGRect) -> NSScreen? {
        guard let primaryHeight = screens.first?.frame.height else { return nil }
        let center = CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
        return screens.first { $0.frame.contains(center) }
    }
}
