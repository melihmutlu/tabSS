import AppKit
import ApplicationServices

/// Observes one app's windows through Accessibility notifications, delivered on the main run loop.
@MainActor
final class AppWatcher {
    enum Event {
        case windowCreated(AXUIElement)
        case focusedWindowChanged(AXUIElement)
        case windowDestroyed(AXUIElement)
        case windowMinimizedChanged(AXUIElement, isMinimized: Bool)
        case windowTitleChanged(AXUIElement)
    }

    private static let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]

    let app: NSRunningApplication
    let element: AXUIElement
    private let observer: AXObserver
    // Removing a run loop source is thread-safe, which lets the nonisolated deinit do it.
    nonisolated(unsafe) private let runLoopSource: CFRunLoopSource
    private let onEvent: (AppWatcher, Event) -> Void

    /// Fails while the app can't answer yet (e.g. still launching); callers retry later. Other registration
    /// errors are tolerated: window list refreshes still keep that app's windows current.
    init?(app: NSRunningApplication, onEvent: @escaping (AppWatcher, Event) -> Void) {
        var observer: AXObserver?
        guard AXObserverCreate(app.processIdentifier, appWatcherCallback, &observer) == .success, let observer else { return nil }
        self.app = app
        self.element = AXUIElementCreateApplication(app.processIdentifier)
        self.observer = observer
        self.runLoopSource = AXObserverGetRunLoopSource(observer)
        self.onEvent = onEvent

        for notification in Self.appNotifications {
            if add(notification, to: element) == .cannotComplete { return nil }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    // The observer callback holds an unretained pointer to self, so stop deliveries before going away.
    deinit {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    func watch(window: AXUIElement) {
        for notification in Self.windowNotifications {
            add(notification, to: window)
        }
    }

    @discardableResult
    private func add(_ notification: String, to target: AXUIElement) -> AXError {
        AXObserverAddNotification(observer, target, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func receive(_ notification: String, for element: AXUIElement) {
        let event: Event? = switch notification {
        case kAXWindowCreatedNotification: .windowCreated(element)
        case kAXFocusedWindowChangedNotification: .focusedWindowChanged(element)
        case kAXUIElementDestroyedNotification: .windowDestroyed(element)
        case kAXWindowMiniaturizedNotification: .windowMinimizedChanged(element, isMinimized: true)
        case kAXWindowDeminiaturizedNotification: .windowMinimizedChanged(element, isMinimized: false)
        case kAXTitleChangedNotification: .windowTitleChanged(element)
        default: nil
        }
        if let event { onEvent(self, event) }
    }
}

// The observer's run loop source is on the main run loop, so this always runs on the main thread.
private func appWatcherCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<AppWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    nonisolated(unsafe) let element = element  // we are on the main thread already; nothing actually crosses threads
    MainActor.assumeIsolated { watcher.receive(name, for: element) }
}
