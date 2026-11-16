import Foundation
import OSLog
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    private static let configuredKey = "launchAtLoginConfigured"
    private static let logger = Logger(subsystem: "local.tabss", category: "LaunchAtLogin")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Starting at login is the default; after the first run (even a failed one), the user's menu choice is respected.
    static func enableOnFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            logger.error("Updating login item failed: \(error.localizedDescription, privacy: .public)")
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
