import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "local.tabss", category: "App")
    private var statusMenu: StatusMenu?
    private let accessibility = AccessibilityPermission()
    private var switcher: Switcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(accessibility: accessibility, isSwitcherRunning: { [weak self] in self?.switcher != nil })
        LaunchAtLogin.enableOnFirstRun()
        accessibility.whenGranted { [weak self] in
            self?.startSwitcher()
        }
    }

    private func startSwitcher() {
        guard switcher == nil else { return }
        let switcher = Switcher()
        guard switcher.start() else {
            logger.error("Could not install the keyboard hook")
            return
        }
        self.switcher = switcher
        ScreenRecordingPermission.request()
    }
}
