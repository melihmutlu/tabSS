import AppKit
import TabssCore

/// What a tile shows; built by the switcher from the window store.
struct TileContent {
    let title: String
    let appName: String
    let icon: NSImage?
    let thumbnail: CGImage?
}

/// The floating, non-activating switcher panel. It never takes focus from the app being switched away from.
@MainActor
final class SwitcherPanel {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private static let cornerRadius: CGFloat = 20
    private static let screenFraction: CGFloat = 0.9

    private let panel: NSPanel
    private let gridView = SwitcherGridView()
    private let metrics = TileLayout.Metrics()

    init() {
        panel = NonActivatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Thumbnails show other windows' contents; ask to be left out of screen sharing (best effort on recent macOS).
        panel.sharingType = .none

        // The system material matches the native switcher and adapts to light/dark, Reduce Transparency and Increase Contrast.
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        background.addSubview(gridView)
        panel.contentView = background

        gridView.onHover = { [weak self] in self?.onHover?($0) }
        gridView.onClick = { [weak self] in self?.onClick?($0) }
    }

    /// How many tiles fit on `screen`; the switcher shows at most this many.
    func capacity(on screen: NSScreen) -> Int {
        TileLayout.capacity(maxPanelSize: maxPanelSize(on: screen), metrics: metrics)
    }

    func show(_ tiles: [TileContent], selectedIndex: Int, on screen: NSScreen) {
        let layout = TileLayout(itemCount: tiles.count, maxPanelSize: maxPanelSize(on: screen), metrics: metrics)
        gridView.update(tiles: tiles, layout: layout, metrics: metrics, selectedIndex: selectedIndex)
        let size = layout.panelSize
        let visible = screen.visibleFrame
        let origin = CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        gridView.frame = CGRect(origin: .zero, size: size)
        panel.orderFrontRegardless()
    }

    func select(_ index: Int) {
        gridView.select(index)
    }

    func hide() {
        panel.orderOut(nil)
        gridView.clear()
    }

    private func maxPanelSize(on screen: NSScreen) -> CGSize {
        CGSize(width: screen.visibleFrame.width * Self.screenFraction, height: screen.visibleFrame.height * Self.screenFraction)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: CGSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lays out tiles from `TileLayout` and turns mouse movement and clicks into tile indices.
private final class SwitcherGridView: NSView {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private var tiles: [WindowTileView] = []
    private var layout: TileLayout?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(tiles contents: [TileContent], layout: TileLayout, metrics: TileLayout.Metrics, selectedIndex: Int) {
        self.layout = layout
        while tiles.count < contents.count {
            let tile = WindowTileView()
            addSubview(tile)
            tiles.append(tile)
        }
        for (index, tile) in tiles.enumerated() {
            guard index < contents.count else {
                tile.isHidden = true
                continue
            }
            let content = contents[index]
            tile.isHidden = false
            tile.frame = layout.tileFrames[index]
            tile.configure(
                title: content.title,
                appName: content.appName,
                icon: content.icon,
                thumbnail: content.thumbnail,
                thumbnailBox: layout.thumbnailSize,
                metrics: metrics
            )
        }
        select(selectedIndex)
    }

    func select(_ index: Int) {
        for (tileIndex, tile) in tiles.enumerated() {
            tile.isSelected = tileIndex == index
        }
        // The panel never takes focus, so VoiceOver hears about the selection through an announcement.
        if index < tiles.count, let label = tiles[index].accessibilityLabel() {
            NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: label, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// Drops images and icons so a hidden panel holds no window content.
    func clear() {
        for tile in tiles {
            tile.configure(title: "", appName: "", icon: nil, thumbnail: nil, thumbnailBox: .zero, metrics: TileLayout.Metrics())
            tile.isSelected = false
            tile.isHidden = true
        }
        layout = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Only real mouse movement selects, so a panel appearing under a resting pointer keeps the keyboard's choice.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        if let index = tileIndex(for: event) { onHover?(index) }
    }

    override func mouseDown(with event: NSEvent) {
        if let index = tileIndex(for: event) { onClick?(index) }
    }

    private func tileIndex(for event: NSEvent) -> Int? {
        layout?.tileIndex(at: convert(event.locationInWindow, from: nil))
    }
}
