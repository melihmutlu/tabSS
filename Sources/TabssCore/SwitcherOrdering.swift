public enum SwitcherItem<Window: Hashable, App: Hashable>: Hashable {
    case window(Window)
    case app(App)
}

extension SwitcherItem: Sendable where Window: Sendable, App: Sendable {}

public enum SwitcherOrdering {
    /// Windows (already most recent first), then windowless apps by recency.
    /// Apps never activated since launch keep their input order after the ranked ones.
    public static func items<Window: Hashable, App: Hashable>(
        windowsByRecency: [Window],
        windowlessApps: [App],
        appRecency: [App]
    ) -> [SwitcherItem<Window, App>] {
        let rank = Dictionary(appRecency.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let apps = windowlessApps.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element] ?? Int.max
                let right = rank[rhs.element] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
        return windowsByRecency.map { .window($0) } + apps.map { .app($0) }
    }
}
