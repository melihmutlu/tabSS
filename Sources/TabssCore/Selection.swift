/// A cursor over `count` items laid out in rows of `columns`: Next/Previous wrap, Up/Down stop at the edges.
public struct Selection: Equatable, Sendable {
    public let count: Int
    public let columns: Int
    public private(set) var index: Int
    // Where a run of Up/Down presses started horizontally, so passing through a short row and back returns
    // to the same tile instead of drifting sideways.
    private var verticalAnchor: Double?

    /// Without `columns`, all items form a single row.
    public init(count: Int, index: Int, columns: Int? = nil) {
        self.count = max(count, 0)
        self.columns = max(columns ?? self.count, 1)
        self.index = Self.clamp(index, count: self.count)
    }

    public var isEmpty: Bool { count == 0 }

    public func contains(_ candidate: Int) -> Bool {
        (0..<count).contains(candidate)
    }

    public mutating func next() {
        guard !isEmpty else { return }
        index = (index + 1) % count
        verticalAnchor = nil
    }

    public mutating func previous() {
        guard !isEmpty else { return }
        index = (index - 1 + count) % count
        verticalAnchor = nil
    }

    /// The tile in the row below drawn closest to where this run of vertical moves started; nothing past the bottom.
    public mutating func down() {
        moveRow(by: 1)
    }

    /// The tile in the row above drawn closest to where this run of vertical moves started; nothing past the top.
    public mutating func up() {
        moveRow(by: -1)
    }

    public mutating func select(_ newIndex: Int) {
        index = Self.clamp(newIndex, count: count)
        verticalAnchor = nil
    }

    private mutating func moveRow(by delta: Int) {
        guard !isEmpty else { return }
        let grid = GridPosition(count: count, columns: columns)
        let anchor = verticalAnchor ?? grid.horizontalPosition(of: index)
        guard let target = grid.nearest(to: anchor, inRow: grid.row(of: index) + delta) else { return }
        index = target
        verticalAnchor = anchor
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
