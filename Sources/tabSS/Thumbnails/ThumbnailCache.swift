import CoreGraphics
import OSLog
import ScreenCaptureKit
import TabssCore

/// Window thumbnails, kept in memory only. Captures happen when a window first appears or is about to lose
/// focus (including when Cmd+Tab starts, since a switch to another Space would take it off screen), never while idle.
@MainActor
final class ThumbnailCache {
    // Twice the tile's thumbnail box, so thumbnails stay sharp on Retina displays.
    private static let maxPixelSize = CGSize(width: 440, height: 280)
    // New windows usually need a moment to draw their first content.
    private static let newWindowDelay: Duration = .milliseconds(500)
    // A thumbnail this fresh is good enough; bounds the work an app flipping focus in a loop can cause.
    private static let minimumCaptureInterval: Duration = .seconds(1)
    // Listing shareable content is the expensive part; an app spamming new windows can't make it continuous.
    private static let minimumFetchInterval: Duration = .seconds(1)
    // Bounds memory (up to ~0.5 MB each) however many windows an app opens; the oldest fall back to app icons.
    private static let maxImages = 128
    private static let permissionRecheckInterval: Duration = .seconds(5)

    private let logger = Logger(subsystem: "local.tabss", category: "Thumbnails")
    private weak var store: WindowStore?
    private var images: [CGWindowID: CGImage] = [:]
    private var lastCaptures: [CGWindowID: ContinuousClock.Instant] = [:]
    private var shareableWindows: [CGWindowID: SCWindow] = [:]
    private var lastFetch: ContinuousClock.Instant?
    private var isPermitted = false
    private var lastPermissionCheck: ContinuousClock.Instant?
    // Never offered for capture (e.g. windows that opt out of screen sharing).
    private var unshareableWindows: Set<CGWindowID> = []
    private var queue: [CGWindowID] = []
    private var isCapturing = false

    /// Observes `store` from now on; create it before the store starts so every window is seen.
    init(store: WindowStore) {
        self.store = store
        store.observer = self
    }

    func image(for id: CGWindowID) -> CGImage? {
        images[id]
    }

    /// Revoking Screen Recording should also take away what was captured before.
    func discardIfPermissionRevoked() {
        guard isPermitted, !ScreenRecordingPermission.isGranted else { return }
        logger.debug("permission revoked: dropping \(self.images.count) thumbnails")
        isPermitted = false
        lastPermissionCheck = .now
        images.removeAll()
        lastCaptures.removeAll()
        shareableWindows.removeAll()
        queue.removeAll()
    }

    /// For a window about to lose focus, e.g. right before switching away from it.
    func capture(_ id: CGWindowID) {
        guard hasPermission(), isKnown(id), !queue.contains(id), !unshareableWindows.contains(id) else {
            logger.debug("skip \(id): permitted=\(self.isPermitted) known=\(self.isKnown(id)) queued=\(self.queue.contains(id)) unshareable=\(self.unshareableWindows.contains(id))")
            return
        }
        if let last = lastCaptures[id], ContinuousClock.now - last < Self.minimumCaptureInterval { return }
        queue.append(id)
        guard !isCapturing else { return }
        isCapturing = true
        Task { await drainQueue() }
    }

    /// The permission check is slow when access is missing, so a "no" is trusted for a while.
    private func hasPermission() -> Bool {
        if isPermitted { return true }
        if let lastPermissionCheck, ContinuousClock.now - lastPermissionCheck < Self.permissionRecheckInterval { return false }
        lastPermissionCheck = .now
        isPermitted = ScreenRecordingPermission.isGranted
        return isPermitted
    }

    private func isKnown(_ id: CGWindowID) -> Bool {
        store?.windows[id] != nil
    }

    private func drainQueue() async {
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard isKnown(id), let image = await captureImage(of: id), isKnown(id) else { continue }
            keep(image, for: id)
        }
        isCapturing = false
    }

    private func keep(_ image: CGImage, for id: CGWindowID) {
        guard isPermitted else { return }  // revoked while this capture was in flight
        images[id] = image
        lastCaptures[id] = .now
        guard images.count > Self.maxImages,
              let oldest = lastCaptures.filter({ images[$0.key] != nil }).min(by: { $0.value < $1.value })?.key
        else { return }
        logger.debug("evict \(oldest): over \(Self.maxImages) thumbnails")
        images[oldest] = nil
    }

    private func captureImage(of id: CGWindowID) async -> CGImage? {
        // Windows on other Spaces keep their contents and capture fine; minimized ones (on no Space) capture blank.
        guard let facts = WindowServer.facts(for: id), facts.isOnScreen || PrivateAPI.isOnAnySpace(id) == true else {
            logger.debug("skip \(id): minimized or gone")
            return nil
        }
        guard let window = await shareableWindow(id) else {
            logger.debug("skip \(id): not in shareable content")
            return nil
        }
        // Never larger than the window itself at 2x, so tiny windows don't become full-size images.
        let bounds = facts.bounds.size
        let limit = CGSize(width: min(Self.maxPixelSize.width, bounds.width * 2), height: min(Self.maxPixelSize.height, bounds.height * 2))
        let size = bounds.aspectFitted(in: limit)
        guard size != .zero else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            logger.debug("capture \(id) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Shareable content is fetched only when a window isn't in the last fetch, and at most once a second.
    private func shareableWindow(_ id: CGWindowID) async -> SCWindow? {
        if let window = shareableWindows[id] { return window }
        if let lastFetch, ContinuousClock.now - lastFetch < Self.minimumFetchInterval { return nil }
        lastFetch = .now
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return nil }
        shareableWindows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        unshareableWindows.subtract(shareableWindows.keys)
        if let window = shareableWindows[id] { return window }
        // Only a window that is still around was really left out on purpose.
        if isKnown(id), WindowServer.facts(for: id) != nil {
            unshareableWindows.insert(id)
        }
        return nil
    }
}

extension ThumbnailCache: WindowStoreObserver {
    func windowStore(_ store: WindowStore, didAdd window: WindowInfo) {
        let id = window.id
        Task { [weak self] in
            try? await Task.sleep(for: Self.newWindowDelay)
            self?.capture(id)
        }
    }

    func windowStore(_ store: WindowStore, didRemove id: CGWindowID) {
        images[id] = nil
        lastCaptures[id] = nil
        shareableWindows[id] = nil
        unshareableWindows.remove(id)
        queue.removeAll { $0 == id }
    }

    func windowStore(_ store: WindowStore, focusDidLeave window: WindowInfo) {
        logger.debug("focus left \(window.id)")
        capture(window.id)
    }
}
