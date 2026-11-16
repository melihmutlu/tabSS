import Testing
@testable import TabssCore

struct MRUListTests {
    @Test func initRemovesDuplicatesKeepingFirst() {
        #expect(MRUList([1, 2, 1, 3, 2]).elements == [1, 2, 3])
    }

    @Test func touchMovesElementToFront() {
        var list = MRUList([1, 2, 3])
        list.touch(3)
        #expect(list.elements == [3, 1, 2])
        list.touch(4)
        #expect(list.elements == [4, 3, 1, 2])
    }

    @Test func focusSequenceProducesReverseOrder() {
        var list = MRUList<String>()
        for window in ["A", "B", "C"] { list.touch(window) }
        #expect(list.elements == ["C", "B", "A"])
    }

    @Test func appendIfAbsentKeepsExistingPosition() {
        var list = MRUList([1, 2])
        list.appendIfAbsent(1)
        list.appendIfAbsent(3)
        #expect(list.elements == [1, 2, 3])
    }

    @Test func removeDropsOnlyThatElement() {
        var list = MRUList([1, 2, 3, 4])
        list.remove(2)
        #expect(list.elements == [1, 3, 4])
    }

    @Test func randomOperationsKeepElementsUniqueAndOrdered() {
        var list = MRUList<Int>()
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func nextRandom(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<2_000 {
            let before = list.elements
            let element = nextRandom(12)
            switch nextRandom(3) {
            case 0:
                list.touch(element)
                #expect(list.elements.first == element)
                #expect(Array(list.elements.dropFirst()) == before.filter { $0 != element })
            case 1:
                list.appendIfAbsent(element)
                #expect(list.elements == (before.contains(element) ? before : before + [element]))
            default:
                list.remove(element)
                #expect(list.elements == before.filter { $0 != element })
            }
            #expect(Set(list.elements).count == list.elements.count)
        }
    }
}
