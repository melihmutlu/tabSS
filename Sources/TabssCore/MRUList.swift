/// Ordered set where the most recently used element comes first.
public struct MRUList<Element: Hashable> {
    public private(set) var elements: [Element] = []

    public init(_ elements: [Element] = []) {
        var seen = Set<Element>()
        self.elements = elements.filter { seen.insert($0).inserted }
    }

    public mutating func touch(_ element: Element) {
        remove(element)
        elements.insert(element, at: 0)
    }

    public mutating func appendIfAbsent(_ element: Element) {
        guard !elements.contains(element) else { return }
        elements.append(element)
    }

    public mutating func remove(_ element: Element) {
        elements.removeAll { $0 == element }
    }
}

extension MRUList: Sendable where Element: Sendable {}
