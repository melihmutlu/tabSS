import AppKit
import TabssCore

/// One switcher tile: thumbnail (or a large app icon), app icon badge and title.
final class WindowTileView: NSView {
    private static let maxBadgeSize: CGFloat = 32
    private static let cornerRadius: CGFloat = 10

    private let imageView = NSImageView()
    private let badgeView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var metrics = TileLayout.Metrics()
    private var thumbnailBox = CGSize.zero
    private var imagePixelSize = CGSize.zero

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            setAccessibilitySelected(isSelected)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        badgeView.imageScaling = .scaleProportionallyUpOrDown
        titleField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.textColor = .labelColor
        for subview in [imageView, badgeView, titleField] {
            subview.setAccessibilityElement(false)  // the tile speaks for itself
            addSubview(subview)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func configure(title: String, appName: String, icon: NSImage?, thumbnail: CGImage?, thumbnailBox: CGSize, metrics: TileLayout.Metrics) {
        self.metrics = metrics
        self.thumbnailBox = thumbnailBox
        titleField.stringValue = title
        setAccessibilityLabel(title == appName ? appName : "\(appName), \(title)")
        if let thumbnail {
            imagePixelSize = CGSize(width: thumbnail.width, height: thumbnail.height)
            imageView.image = NSImage(cgImage: thumbnail, size: .zero)
            badgeView.image = icon
            badgeView.isHidden = false
        } else {
            imagePixelSize = .zero
            imageView.image = icon
            badgeView.image = nil
            badgeView.isHidden = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset = metrics.tileInset
        let box = CGRect(origin: CGPoint(x: inset, y: inset), size: thumbnailBox)
        if badgeView.isHidden {
            // Without a thumbnail the app icon stands in, at a size that reads as an icon rather than a picture.
            let side = (min(box.width, box.height) * 2 / 3).rounded()
            imageView.frame = CGRect(x: (box.midX - side / 2).rounded(), y: (box.midY - side / 2).rounded(), width: side, height: side)
        } else {
            let picture = imagePixelSize.aspectFitted(in: box.size)
            imageView.frame = CGRect(
                x: (box.midX - picture.width / 2).rounded(),
                y: (box.midY - picture.height / 2).rounded(),
                width: picture.width,
                height: picture.height
            )
            // The badge hangs off the picture's lower-left corner and shrinks with small tiles.
            let badge = min(Self.maxBadgeSize, (box.height * 0.4).rounded())
            badgeView.frame = CGRect(x: imageView.frame.minX - badge / 4, y: imageView.frame.maxY - badge * 3 / 4, width: badge, height: badge).integral
        }
        titleField.frame = CGRect(
            x: inset,
            y: box.maxY + metrics.titleSpacing,
            width: bounds.width - 2 * inset,
            height: metrics.titleHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
    }
}
