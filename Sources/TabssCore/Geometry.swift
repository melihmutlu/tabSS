import CoreGraphics

extension CGSize {
    /// The largest size with this aspect ratio that fits in `bounds`, in whole units and never zero.
    public func aspectFitted(in bounds: CGSize) -> CGSize {
        guard width > 0, height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = Swift.min(bounds.width / width, bounds.height / height)
        // Rounding must not push a side past a fractional bound.
        func side(_ length: CGFloat, within limit: CGFloat) -> CGFloat {
            Swift.max(Swift.min((length * scale).rounded(), limit.rounded(.down)), 1)
        }
        return CGSize(width: side(width, within: bounds.width), height: side(height, within: bounds.height))
    }
}
