import CoreGraphics

/// Decides whether an Accessibility window is a real, user-facing window worth listing.
public enum WindowEligibility {
    public static let standardSubrole = "AXStandardWindow"
    public static let dialogSubrole = "AXDialog"
    public static let normalWindowLayer = 0
    public static let minimumSide: CGFloat = 20

    public static func isSwitchable(subrole: String?, layer: Int, size: CGSize) -> Bool {
        guard let subrole, subrole == standardSubrole || subrole == dialogSubrole else { return false }
        return layer == normalWindowLayer && size.width >= minimumSide && size.height >= minimumSide
    }
}
