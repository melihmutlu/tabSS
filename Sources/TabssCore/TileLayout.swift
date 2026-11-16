import CoreGraphics

/// Grid geometry for the switcher panel, in a top-left-origin (flipped) coordinate space.
public struct TileLayout: Equatable, Sendable {
    public struct Metrics: Equatable, Sendable {
        public var thumbnailSize = CGSize(width: 220, height: 140)
        public var tileInset: CGFloat = 10
        public var titleHeight: CGFloat = 18
        public var titleSpacing: CGFloat = 6
        public var tileSpacing: CGFloat = 4
        public var panelPadding: CGFloat = 16
        public var minimumScale: CGFloat = 0.4

        public init() {}
    }

    public let scale: CGFloat
    public let tileSize: CGSize
    public let thumbnailSize: CGSize
    public let columns: Int
    public let panelSize: CGSize
    public let tileFrames: [CGRect]

    public init(itemCount: Int, maxPanelSize: CGSize, metrics: Metrics = Metrics()) {
        let count = max(itemCount, 0)
        var scale: CGFloat = 1
        var grid = Self.grid(count: count, scale: scale, maxWidth: maxPanelSize.width, metrics: metrics)
        while grid.panelHeight > maxPanelSize.height, scale > metrics.minimumScale {
            scale = max(scale - 0.05, metrics.minimumScale)
            grid = Self.grid(count: count, scale: scale, maxWidth: maxPanelSize.width, metrics: metrics)
        }

        self.scale = scale
        tileSize = grid.tileSize
        thumbnailSize = Self.thumbnailSize(scale: scale, metrics: metrics)
        columns = grid.columns
        panelSize = CGSize(width: grid.panelWidth, height: grid.panelHeight)
        tileFrames = Self.frames(count: count, grid: grid, metrics: metrics)
    }

    public func tileIndex(at point: CGPoint) -> Int? {
        tileFrames.firstIndex { $0.contains(point) }
    }

    /// The most tiles that fit at minimum scale; callers show at most this many.
    public static func capacity(maxPanelSize: CGSize, metrics: Metrics = Metrics()) -> Int {
        let tile = grid(count: 1, scale: metrics.minimumScale, maxWidth: maxPanelSize.width, metrics: metrics).tileSize
        return cells(fitting: maxPanelSize.width, of: tile.width, metrics: metrics)
            * cells(fitting: maxPanelSize.height, of: tile.height, metrics: metrics)
    }

    private struct Grid {
        let tileSize: CGSize
        let columns: Int
        let panelWidth: CGFloat
        let panelHeight: CGFloat
    }

    // Whole points keep tile edges and text crisp on 1x displays.
    private static func thumbnailSize(scale: CGFloat, metrics: Metrics) -> CGSize {
        CGSize(
            width: (metrics.thumbnailSize.width * scale).rounded(),
            height: (metrics.thumbnailSize.height * scale).rounded()
        )
    }

    private static func grid(count: Int, scale: CGFloat, maxWidth: CGFloat, metrics: Metrics) -> Grid {
        let thumbnail = thumbnailSize(scale: scale, metrics: metrics)
        let tileSize = CGSize(
            width: thumbnail.width + 2 * metrics.tileInset,
            height: thumbnail.height + metrics.titleSpacing + metrics.titleHeight + 2 * metrics.tileInset
        )
        let columns = max(min(count, cells(fitting: maxWidth, of: tileSize.width, metrics: metrics)), 1)
        let rows = max((count + columns - 1) / columns, 1)
        return Grid(
            tileSize: tileSize,
            columns: columns,
            panelWidth: span(columns, of: tileSize.width, metrics: metrics),
            panelHeight: span(rows, of: tileSize.height, metrics: metrics)
        )
    }

    private static func cells(fitting length: CGFloat, of cellLength: CGFloat, metrics: Metrics) -> Int {
        let usable = length - 2 * metrics.panelPadding + metrics.tileSpacing
        return max(Int(usable / (cellLength + metrics.tileSpacing)), 1)
    }

    private static func span(_ cells: Int, of length: CGFloat, metrics: Metrics) -> CGFloat {
        CGFloat(cells) * length + CGFloat(cells - 1) * metrics.tileSpacing + 2 * metrics.panelPadding
    }

    private static func frames(count: Int, grid: Grid, metrics: Metrics) -> [CGRect] {
        let step = CGSize(width: grid.tileSize.width + metrics.tileSpacing, height: grid.tileSize.height + metrics.tileSpacing)
        return (0..<count).map { index in
            let row = index / grid.columns
            // Left-aligned rows keep a short last row in the same columns Up and Down move through.
            let column = index % grid.columns
            return CGRect(
                origin: CGPoint(
                    x: metrics.panelPadding + CGFloat(column) * step.width,
                    y: metrics.panelPadding + CGFloat(row) * step.height
                ),
                size: grid.tileSize
            )
        }
    }
}
