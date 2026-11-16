import AppKit

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let accessibility: AccessibilityPermission
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Grant Accessibility…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let screenRecordingItem = NSMenuItem(title: "Grant Screen Recording…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")

    init(accessibility: AccessibilityPermission) {
        self.accessibility = accessibility
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "tabSS")

        for item in [launchAtLoginItem, accessibilityItem, screenRecordingItem] {
            item.target = self
        }
        let quitItem = NSMenuItem(title: "Quit tabSS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let menu = NSMenu()
        menu.delegate = self
        menu.items = [launchAtLoginItem, accessibilityItem, screenRecordingItem, .separator(), quitItem]
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        accessibilityItem.isHidden = accessibility.isGranted
        screenRecordingItem.isHidden = !accessibility.isGranted || ScreenRecordingPermission.isGranted
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
    }

    @objc private func openAccessibilitySettings() {
        accessibility.openSettings()
    }

    @objc private func openScreenRecordingSettings() {
        ScreenRecordingPermission.openSettings()
    }
}
