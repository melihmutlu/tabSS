import CoreGraphics

extension CGSize {
    /// The largest size with this aspect ratio that fits in `bounds`, in whole units and never zero.
    public func aspectFitted(in bounds: CGSize) -> CGSize {
        guard width > 0, height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = Swift.min(bounds.width / width, bounds.height / height)
        return CGSize(width: Swift.max((width * scale).rounded(), 1), height: Swift.max((height * scale).rounded(), 1))
    }
}
