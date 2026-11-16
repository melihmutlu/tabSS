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

    /// One row down; from the last row it wraps to the top of the same column.
    public mutating func down() {
        guard !isEmpty else { return }
        let below = index + columns
        index = below < count ? below : index % columns
    }

    /// One row up; from the first row it wraps to the bottom of the same column, or the last item if that row is short.
    public mutating func up() {
        guard !isEmpty else { return }
        guard index < columns else {
            index -= columns
            return
        }
        let lastRowStart = (count - 1) / columns * columns
        index = min(lastRowStart + index, count - 1)
    }

    public mutating func select(_ newIndex: Int) {
        index = Self.clamp(newIndex, count: count)
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
