/// How much of a resource something used within a rolling window, e.g. main-thread time spent on one app.
public struct UsageBudget: Sendable {
    public let limit: Duration
    public let window: Duration
    private var windowStart: ContinuousClock.Instant?
    private var used: Duration = .zero

    public init(limit: Duration, per window: Duration) {
        self.limit = limit
        self.window = window
    }

    /// Records `cost` spent at `now`; returns whether usage in the current window is over the limit.
    public mutating func charge(_ cost: Duration, at now: ContinuousClock.Instant) -> Bool {
        if let windowStart, now - windowStart < window {
            used += cost
        } else {
            windowStart = now
            used = cost
        }
        return used > limit
    }
}
