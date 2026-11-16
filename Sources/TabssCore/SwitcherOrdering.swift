public enum SwitcherItem<Window: Hashable, App: Hashable>: Hashable {
    case window(Window)
    case app(App)
}

extension SwitcherItem: Sendable where Window: Sendable, App: Sendable {}

public enum SwitcherOrdering {
    /// Windows by recency, then windowless apps by recency. Items missing from a recency list keep their input order after the ranked ones.
    public static func items<Window: Hashable, App: Hashable>(
        windows: [Window],
        windowRecency: [Window],
        windowlessApps: [App],
        appRecency: [App]
    ) -> [SwitcherItem<Window, App>] {
        sorted(windows, by: windowRecency).map { .window($0) }
            + sorted(windowlessApps, by: appRecency).map { .app($0) }
    }

    private static func sorted<Element: Hashable>(_ elements: [Element], by recency: [Element]) -> [Element] {
        let rank = Dictionary(recency.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return elements.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element] ?? Int.max
                let right = rank[rhs.element] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }
}
