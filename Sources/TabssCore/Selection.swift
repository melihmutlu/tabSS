/// A wrap-around cursor over `count` items.
public struct Selection: Equatable, Sendable {
    public let count: Int
    public private(set) var index: Int

    public init(count: Int, index: Int) {
        self.count = max(count, 0)
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

    public mutating func select(_ newIndex: Int) {
        index = Self.clamp(newIndex, count: count)
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
