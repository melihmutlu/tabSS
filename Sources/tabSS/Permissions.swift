import AppKit
import ApplicationServices

private func openPrivacySettings(_ anchor: String) {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
    NSWorkspace.shared.open(url)
}

/// Accessibility is required for the event tap and for reading/focusing windows.
@MainActor
final class AccessibilityPermission {
    private var waitTask: Task<Void, Never>?

    var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt if needed, then calls `onGranted` once access is granted, without a relaunch.
    func whenGranted(_ onGranted: @escaping @MainActor () -> Void) {
        // `kAXTrustedCheckOptionPrompt` is a global var Swift 6 rejects as not concurrency-safe; this is its value.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            onGranted()
            return
        }
        // There is no public notification for the grant, so check once per second until it happens.
        waitTask = Task { @MainActor in
            while !AXIsProcessTrusted() {
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(500))
                if Task.isCancelled { return }
            }
            onGranted()
        }
    }

    func openSettings() {
        openPrivacySettings("Privacy_Accessibility")
    }
}

/// Screen Recording is optional: without it, tiles show app icons instead of thumbnails.
@MainActor
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// The system prompts only on the first request; later calls return silently.
    static func request() {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        request()  // makes sure tabSS is listed in Settings
        openPrivacySettings("Privacy_ScreenCapture")
    }
}
