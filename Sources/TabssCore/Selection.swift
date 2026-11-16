/// A wrap-around cursor over `count` items laid out in rows of `columns`.
public struct Selection: Equatable, Sendable {
    public let count: Int
    public let columns: Int
    public private(set) var index: Int

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
    }

    public mutating func previous() {
        guard !isEmpty else { return }
        index = (index - 1 + count) % count
    }

    /// The nearest tile in the row below, as drawn; nothing past the bottom row.
    public mutating func down() {
        moveRow(by: 1)
    }

    /// The nearest tile in the row above, as drawn; nothing past the top row.
    public mutating func up() {
        moveRow(by: -1)
    }

    private mutating func moveRow(by delta: Int) {
        guard !isEmpty, let target = GridPosition(count: count, columns: columns).nearest(to: index, rowDelta: delta) else { return }
        index = target
    }

    public mutating func select(_ newIndex: Int) {
        index = Self.clamp(newIndex, count: count)
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
