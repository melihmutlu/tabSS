import CoreGraphics
import Testing
@testable import TabssCore

struct GeometryTests {
    private let box = CGSize(width: 440, height: 280)

    @Test func wideWindowsFitTheWidth() {
        #expect(CGSize(width: 1920, height: 1080).aspectFitted(in: box) == CGSize(width: 440, height: 248))
    }

    @Test func tallWindowsFitTheHeight() {
        #expect(CGSize(width: 600, height: 1200).aspectFitted(in: box) == CGSize(width: 140, height: 280))
    }

    @Test func smallWindowsScaleUpToTheBox() {
        #expect(CGSize(width: 220, height: 140).aspectFitted(in: box) == box)
    }

    @Test func extremeAspectRatiosNeverCollapseToZero() {
        #expect(CGSize(width: 10_000, height: 1).aspectFitted(in: box) == CGSize(width: 440, height: 1))
    }

    @Test func emptySizesFitToZero() {
        #expect(CGSize.zero.aspectFitted(in: box) == .zero)
        #expect(CGSize(width: 100, height: 100).aspectFitted(in: .zero) == .zero)
    }

    @Test func degenerateOrNegativeSizesFitToZero() {
        #expect(CGSize(width: 0, height: 100).aspectFitted(in: box) == .zero)
        #expect(CGSize(width: 100, height: 0).aspectFitted(in: box) == .zero)
        #expect(CGSize(width: -100, height: 50).aspectFitted(in: box) == .zero)
        #expect(CGSize(width: 100, height: 50).aspectFitted(in: CGSize(width: -440, height: 280)) == .zero)
        #expect(CGSize(width: CGFloat.nan, height: 50).aspectFitted(in: box) == .zero)
    }

    @Test func matchingAspectRatioFillsTheBoxExactly() {
        #expect(CGSize(width: 880, height: 560).aspectFitted(in: box) == box)
        #expect(box.aspectFitted(in: box) == box)
    }

    @Test func extremeTallWindowsNeverCollapseToZero() {
        #expect(CGSize(width: 1, height: 10_000).aspectFitted(in: box) == CGSize(width: 1, height: 280))
    }

    @Test func fractionalPointSizesRoundToWholePixels() {
        let fitted = CGSize(width: 1000.5, height: 333.3).aspectFitted(in: box)
        #expect(fitted.width == 440)
        #expect(fitted.height == fitted.height.rounded())
    }

    /// The fitted size feeds `SCStreamConfiguration`'s integer width and height, so it must stay within
    /// the box, fill it on the limiting side, and keep the aspect ratio up to rounding.
    @Test(arguments: [
        CGSize(width: 1, height: 1), CGSize(width: 3, height: 7), CGSize(width: 333, height: 211),
        CGSize(width: 1280, height: 800), CGSize(width: 1512, height: 982), CGSize(width: 2560, height: 1440),
        CGSize(width: 800, height: 2000), CGSize(width: 5120, height: 2880), CGSize(width: 441, height: 281),
        CGSize(width: 439, height: 279), CGSize(width: 6016, height: 25),
    ])
    func staysInsideTheBoxFillsOneSideAndKeepsAspect(size: CGSize) {
        let fitted = size.aspectFitted(in: box)
        #expect(fitted.width >= 1 && fitted.height >= 1)
        #expect(fitted.width <= box.width && fitted.height <= box.height)
        #expect(fitted.width == box.width || fitted.height == box.height)
        #expect(fitted.width == fitted.width.rounded() && fitted.height == fitted.height.rounded())
        let scale = min(box.width / size.width, box.height / size.height)
        #expect(abs(fitted.width - size.width * scale) <= 0.5 || fitted.width == 1)
        #expect(abs(fitted.height - size.height * scale) <= 0.5 || fitted.height == 1)
    }
}
