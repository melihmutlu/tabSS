import CoreGraphics
import Testing
@testable import TabssCore

struct WindowEligibilityTests {
    private let normalSize = CGSize(width: 800, height: 600)

    @Test func acceptsStandardWindowsAndDialogs() {
        #expect(WindowEligibility.isSwitchable(subrole: "AXStandardWindow", layer: 0, size: normalSize))
        #expect(WindowEligibility.isSwitchable(subrole: "AXDialog", layer: 0, size: normalSize))
    }

    @Test func rejectsOtherSubroles() {
        for subrole in ["AXFloatingWindow", "AXSystemDialog", "AXUnknown", nil] as [String?] {
            #expect(!WindowEligibility.isSwitchable(subrole: subrole, layer: 0, size: normalSize))
        }
    }

    @Test func rejectsNonNormalLayersAndTinyWindows() {
        #expect(!WindowEligibility.isSwitchable(subrole: "AXStandardWindow", layer: 3, size: normalSize))
        #expect(!WindowEligibility.isSwitchable(subrole: "AXStandardWindow", layer: -2147483623, size: normalSize))
        #expect(!WindowEligibility.isSwitchable(subrole: "AXStandardWindow", layer: 0, size: CGSize(width: 1, height: 1)))
    }

    @Test func minimumSideIsInclusive() {
        let side = WindowEligibility.minimumSide
        #expect(WindowEligibility.isSwitchable(subrole: "AXStandardWindow", layer: 0, size: CGSize(width: side, height: side)))
        #expect(!WindowEligibility.isSwitchable(subrole: "AXStandardWindow", layer: 0, size: CGSize(width: side - 0.5, height: 600)))
        #expect(!WindowEligibility.isSwitchable(subrole: "AXStandardWindow", layer: 0, size: CGSize(width: 800, height: side - 0.5)))
    }

    @Test func subroleMatchIsExact() {
        for subrole in ["", "axstandardwindow", "AXStandardWindow ", "AXDialogs"] {
            #expect(!WindowEligibility.isSwitchable(subrole: subrole, layer: 0, size: normalSize))
        }
    }

    @Test func dialogsFollowTheSameLayerAndSizeRules() {
        #expect(!WindowEligibility.isSwitchable(subrole: "AXDialog", layer: 8, size: CGSize(width: 400, height: 300)))
        #expect(!WindowEligibility.isSwitchable(subrole: "AXDialog", layer: 0, size: CGSize(width: 400, height: 10)))
    }
}
