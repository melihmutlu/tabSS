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

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        let ignorable = properties.isDefaultIgnorableCodePoint || properties.generalCategory == .format
        return properties.isBidiControl || (ignorable && !shapesVisibleText(scalar))
    }

    /// Invisible on their own, but needed by emoji, flags and some scripts to render correctly.
    private static func shapesVisibleText(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200C, 0x200D: true  // zero-width non-joiner and joiner
        case 0xFE00...0xFE0F, 0xE0100...0xE01EF: true  // variation selectors
        case 0xE0020...0xE007F: true  // tag characters (subdivision flags)
        default: false
        }
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
