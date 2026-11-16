/// Where items sit in a grid of `columns` whose partly filled last row is centered, like the native switcher.
/// Shared by the drawing (TileLayout) and the arrow keys (Selection), so what moves is what is seen.
public struct GridPosition: Equatable, Sendable {
    public let count: Int
    public let columns: Int

    public init(count: Int, columns: Int) {
        self.count = max(count, 0)
        self.columns = max(columns, 1)
    }

    public var rows: Int { (count + columns - 1) / columns }

    public func row(of index: Int) -> Int { index / columns }

    public func indices(inRow row: Int) -> Range<Int> {
        let start = row * columns
        return start..<min(start + columns, count)
    }

    /// Horizontal position in column widths; a short row is shifted by half the missing columns.
    public func horizontalPosition(of index: Int) -> Double {
        let missing = columns - indices(inRow: row(of: index)).count
        return Double(index % columns) + Double(missing) / 2
    }

    /// The item in the row `rowDelta` away that is drawn closest to `index` horizontally, or nil past the edge.
    public func nearest(to index: Int, rowDelta: Int) -> Int? {
        let target = row(of: index) + rowDelta
        guard (0..<rows).contains(target) else { return nil }
        let position = horizontalPosition(of: index)
        // On a tie (exactly between two tiles), the left one wins.
        return indices(inRow: target).min { abs(horizontalPosition(of: $0) - position) < abs(horizontalPosition(of: $1) - position) }
    }
}
