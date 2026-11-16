/// Text from other apps, made safe to show.
public enum DisplayText {
    /// Drops invisible and text-direction characters an app could use to disguise a title, turns line breaks
    /// and other control characters into spaces, trims, and falls back when nothing visible is left.
    public static func title(_ raw: String, fallback: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where !isInvisible(scalar) {
            scalars.append(isLineBreakOrControl(scalar) ? " " : scalar)
        }
        let title = String(scalars).trimmingWhitespace()
        return title.isEmpty ? fallback : title
    }

    private static let zeroWidthJoiners: Set<UInt32> = [0x200C, 0x200D]  // needed by emoji sequences and some scripts

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isBidiControl
            || (scalar.properties.generalCategory == .format && !zeroWidthJoiners.contains(scalar.value))
    }

    private static func isLineBreakOrControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: true
        default: false
        }
    }
}

private extension String {
    func trimmingWhitespace() -> String {
        let scalars = unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace })
        else { return "" }
        return String(scalars[first...last])
    }
}
