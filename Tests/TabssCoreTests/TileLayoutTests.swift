import CoreGraphics
import Testing
@testable import TabssCore

struct TileLayoutTests {
    private let metrics = TileLayout.Metrics()
    private let largeScreen = CGSize(width: 3000, height: 2000)

    @Test func singleRowFitsAllItems() {
        let layout = TileLayout(itemCount: 3, maxPanelSize: largeScreen)
        #expect(layout.columns == 3)
        #expect(layout.scale == 1)
        #expect(layout.tileFrames.count == 3)
        #expect(layout.tileFrames[0].minX == metrics.panelPadding)
        #expect(layout.panelSize.width == layout.tileFrames[2].maxX + metrics.panelPadding)
    }

    @Test func wrapsIntoRowsWithTheLastRowLeftAligned() {
        let width = 3 * 240 + 2 * metrics.tileSpacing + 2 * metrics.panelPadding
        let layout = TileLayout(itemCount: 4, maxPanelSize: CGSize(width: width, height: 2000))
        #expect(layout.columns == 3)
        let lastRowTile = layout.tileFrames[3]
        #expect(lastRowTile.minY > layout.tileFrames[0].maxY)
        #expect(lastRowTile.minX == layout.tileFrames[0].minX)
    }

    @Test func neverShrinksBelowMinimumScale() {
        let layout = TileLayout(itemCount: 500, maxPanelSize: CGSize(width: 800, height: 400))
        #expect(layout.scale == metrics.minimumScale)
    }

    @Test func tilesNeverOverlap() {
        let layout = TileLayout(itemCount: 13, maxPanelSize: CGSize(width: 1200, height: 900))
        for (i, a) in layout.tileFrames.enumerated() {
            for b in layout.tileFrames[(i + 1)...] {
                #expect(!a.intersects(b))
            }
        }
    }

    @Test func emptyLayoutHasNoTiles() {
        let layout = TileLayout(itemCount: 0, maxPanelSize: largeScreen)
        #expect(layout.tileFrames.isEmpty)
        #expect(layout.columns == 1)
    }

    @Test func tileSizeFollowsMetricsAtFullScale() {
        let layout = TileLayout(itemCount: 1, maxPanelSize: largeScreen)
        #expect(layout.tileSize == CGSize(width: 240, height: 140 + 6 + 18 + 20))
        #expect(layout.thumbnailSize == metrics.thumbnailSize)
        #expect(layout.panelSize == CGSize(width: 240 + 32, height: 184 + 32))
    }

    @Test func exactWidthFitBoundary() {
        let width = 3 * 240 + 2 * metrics.tileSpacing + 2 * metrics.panelPadding
        #expect(TileLayout(itemCount: 10, maxPanelSize: CGSize(width: width, height: 5000)).columns == 3)
        #expect(TileLayout(itemCount: 10, maxPanelSize: CGSize(width: width - 0.5, height: 5000)).columns == 2)
    }

    @Test func tooNarrowFallsBackToOneColumn() {
        let layout = TileLayout(itemCount: 3, maxPanelSize: CGSize(width: 50, height: 5000))
        #expect(layout.columns == 1)
        #expect(layout.tileFrames.map(\.minX) == [16, 16, 16])
    }

    @Test func negativeItemCountIsTreatedAsEmpty() {
        let layout = TileLayout(itemCount: -4, maxPanelSize: largeScreen)
        #expect(layout.tileFrames.isEmpty)
        #expect(layout == TileLayout(itemCount: 0, maxPanelSize: largeScreen))
    }

    @Test func shrinkingScalesThumbnailAndAddsColumns() {
        let fullScale = TileLayout(itemCount: 40, maxPanelSize: CGSize(width: 1400, height: 100_000))
        let shrunk = TileLayout(itemCount: 40, maxPanelSize: CGSize(width: 1400, height: 800))
        #expect(shrunk.columns > fullScale.columns)
        #expect(abs(shrunk.thumbnailSize.width - metrics.thumbnailSize.width * shrunk.scale) < 0.001)
        #expect(abs(shrunk.thumbnailSize.height - metrics.thumbnailSize.height * shrunk.scale) < 0.001)
    }

    @Test func shrinksOnlyAsMuchAsNeeded() {
        // Two rows of 184pt tiles need 2*184 + 4 + 32 = 404pt; one point less forces a step down.
        let fits = TileLayout(itemCount: 2, maxPanelSize: CGSize(width: 300, height: 404))
        #expect(fits.scale == 1)
        let tight = TileLayout(itemCount: 2, maxPanelSize: CGSize(width: 300, height: 403))
        #expect(tight.scale < 1)
        #expect(tight.scale > 0.9)
        #expect(tight.panelSize.height <= 403)
    }

    @Test(arguments: [1, 2, 5, 7, 12, 25, 60])
    func tilesStayInsidePanelInReadingOrder(count: Int) {
        let layout = TileLayout(itemCount: count, maxPanelSize: CGSize(width: 1440, height: 900))
        let panel = CGRect(origin: .zero, size: layout.panelSize)
        #expect(layout.panelSize.width <= 1440)
        for (index, frame) in layout.tileFrames.enumerated() {
            #expect(panel.insetBy(dx: metrics.panelPadding - 0.001, dy: metrics.panelPadding - 0.001).contains(frame))
            #expect(frame.size == layout.tileSize)
            if index > 0 {
                let previous = layout.tileFrames[index - 1]
                #expect(frame.minY > previous.minY || (frame.minY == previous.minY && frame.minX > previous.maxX))
            }
        }
    }

    @Test func rowsStartAtThePaddingAndFullRowsSpanThePanel() {
        let width = 3 * 240 + 2 * metrics.tileSpacing + 2 * metrics.panelPadding
        let layout = TileLayout(itemCount: 5, maxPanelSize: CGSize(width: width, height: 5000))
        #expect(layout.tileFrames[0].minX == metrics.panelPadding)
        #expect(layout.tileFrames[2].maxX == layout.panelSize.width - metrics.panelPadding)
        #expect(layout.tileFrames[3].minX == metrics.panelPadding)
    }

    @Test func hitTestingEdgesAndGaps() {
        let layout = TileLayout(itemCount: 2, maxPanelSize: largeScreen)
        let first = layout.tileFrames[0]
        #expect(layout.tileIndex(at: CGPoint(x: first.minX, y: first.minY)) == 0)
        #expect(layout.tileIndex(at: CGPoint(x: first.maxX + metrics.tileSpacing / 2, y: first.midY)) == nil)
        #expect(layout.tileIndex(at: CGPoint(x: first.midX, y: first.maxY + 1)) == nil)
        #expect(layout.tileIndex(at: CGPoint(x: layout.tileFrames[1].maxX - 0.5, y: first.midY)) == 1)
    }

    @Test(arguments: [(9, 700.0), (17, 900.0), (40, 800.0), (75, 1000.0), (200, 1100.0)])
    func shrunkLayoutsStayPixelAlignedAndInBounds(count: Int, height: CGFloat) {
        let maxSize = CGSize(width: 1300, height: height)
        let layout = TileLayout(itemCount: count, maxPanelSize: maxSize)
        #expect(layout.scale >= metrics.minimumScale && layout.scale <= 1)
        if layout.scale > metrics.minimumScale {
            #expect(layout.panelSize.height <= maxSize.height)
        }
        #expect(layout.panelSize.width <= maxSize.width)
        #expect(layout.tileFrames.count == count)
        let isWhole = { (value: CGFloat) in value == value.rounded() }
        #expect(isWhole(layout.tileSize.width) && isWhole(layout.tileSize.height))
        for frame in layout.tileFrames {
            #expect(isWhole(frame.minX) && isWhole(frame.minY))
            #expect(frame.maxX <= layout.panelSize.width - metrics.panelPadding + 0.001)
            #expect(frame.maxY <= layout.panelSize.height - metrics.panelPadding + 0.001)
        }
    }

    @Test func shrinkingStopsAtFirstFittingStep() {
        // The loop steps down by 0.05; the result must fit, and the step above it must not.
        let maxSize = CGSize(width: 1300, height: 800)
        let layout = TileLayout(itemCount: 40, maxPanelSize: maxSize)
        #expect(layout.scale < 1)
        var larger = metrics
        larger.thumbnailSize = CGSize(width: metrics.thumbnailSize.width * (layout.scale + 0.05),
                                      height: metrics.thumbnailSize.height * (layout.scale + 0.05))
        larger.minimumScale = 1
        #expect(TileLayout(itemCount: 40, maxPanelSize: maxSize, metrics: larger).panelSize.height > maxSize.height)
    }

    // Callers truncate the item list to `capacity`: too high overflows the screen, too low hides windows that would fit.
    @Test(arguments: [(1300.0, 800.0), (800.0, 600.0), (2560.0, 1400.0), (1023.5, 701.0), (300.0, 250.0)])
    func capacityIsExactlyWhatFitsAtMinimumScale(width: CGFloat, height: CGFloat) {
        let maxSize = CGSize(width: width, height: height)
        let capacity = TileLayout.capacity(maxPanelSize: maxSize)
        let full = TileLayout(itemCount: capacity, maxPanelSize: maxSize)
        #expect(full.panelSize.width <= maxSize.width)
        #expect(full.panelSize.height <= maxSize.height)
        let overfull = TileLayout(itemCount: capacity + 1, maxPanelSize: maxSize)
        #expect(overfull.scale == TileLayout.Metrics().minimumScale)
        #expect(overfull.panelSize.height > maxSize.height)
    }

    @Test func capacityIsAtLeastOne() {
        #expect(TileLayout.capacity(maxPanelSize: CGSize(width: 10, height: 10)) == 1)
    }
}
