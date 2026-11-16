import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
    private let accessibility = AccessibilityPermission()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(accessibility: accessibility)
        LaunchAtLogin.enableOnFirstRun()
        accessibility.whenGranted { [weak self] in
            self?.startSwitcher()
        }
    }

    private func startSwitcher() {
        ScreenRecordingPermission.request()
    }
}
