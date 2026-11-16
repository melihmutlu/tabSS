import AppKit
import ApplicationServices

/// Brings a window or app to the front.
final class WindowActivator: Sendable {
    // Accessibility calls into a slow app can block, so they never run on the main thread.
    private let queue = DispatchQueue(label: "tabSS.activation", qos: .userInteractive)

    func activate(_ window: WindowInfo) {
        let target = ActivationTarget(window: window)
        queue.async { target.activate() }
    }

    @MainActor
    func activate(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }  // reopening its bundle would relaunch it
        guard let bundleURL = app.bundleURL else {
            // Without a bundle there is nothing to reopen; Accessibility can still bring it forward.
            let element = UncheckedElement(element: AXUIElementCreateApplication(app.processIdentifier))
            queue.async { AX.set(element.element, kAXFrontmostAttribute, to: kCFBooleanTrue) }
            return
        }
        // Like a Dock click: the app gets a reopen event and usually opens its main window.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
    }
}

private struct UncheckedElement: @unchecked Sendable {  // AXUIElement is an immutable, thread-safe CF object
    let element: AXUIElement
}

/// The parts of a window needed to focus it, safe to hand to the activation queue.
private struct ActivationTarget: @unchecked Sendable {  // AXUIElement is an immutable, thread-safe CF object
    let windowID: CGWindowID
    let pid: pid_t
    let window: AXUIElement
    let app: AXUIElement

    init(window: WindowInfo) {
        windowID = window.id
        pid = window.app.processIdentifier
        self.window = window.element
        app = AXUIElementCreateApplication(pid)
    }

    func activate() {
        if AX.bool(window, kAXMinimizedAttribute) == true {
            AX.set(window, kAXMinimizedAttribute, to: kCFBooleanFalse)
        }
        if AX.bool(app, kAXHiddenAttribute) == true {
            AX.set(app, kAXHiddenAttribute, to: kCFBooleanFalse)
        }
        if !PrivateAPI.focus(windowID: windowID, pid: pid) {
            AX.set(app, kAXFrontmostAttribute, to: kCFBooleanTrue)
            AX.set(window, kAXMainAttribute, to: kCFBooleanTrue)
        }
        AX.perform(window, kAXRaiseAction)
    }
}
