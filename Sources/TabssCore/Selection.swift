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

    /// The tile directly below; in a short last row, the last tile; from the bottom row, the top of the column.
    /// With a single row it moves to the next tile, like the arrow keys in the native switcher.
    public mutating func down() {
        guard !isEmpty else { return }
        guard rows > 1 else { return next() }
        let below = index + columns
        if below < count {
            index = below
        } else if index / columns < rows - 1 {
            index = count - 1
        } else {
            index %= columns
        }
    }

    /// The tile directly above; from the top row, the lowest tile in the same column.
    /// With a single row it moves to the previous tile.
    public mutating func up() {
        guard !isEmpty else { return }
        guard rows > 1 else { return previous() }
        guard index < columns else {
            index -= columns
            return
        }
        let bottom = (rows - 1) * columns + index
        index = bottom < count ? bottom : bottom - columns
    }

    private var rows: Int { (count + columns - 1) / columns }

    public mutating func select(_ newIndex: Int) {
        index = Self.clamp(newIndex, count: count)
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
