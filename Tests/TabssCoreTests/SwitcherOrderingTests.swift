import Testing
@testable import TabssCore

struct SwitcherOrderingTests {
    @Test func windowsFollowRecencyThenWindowlessApps() {
        let items = SwitcherOrdering.items(
            windows: [10, 20, 30],
            windowRecency: [30, 10],
            windowlessApps: ["mail", "music"],
            appRecency: ["music"]
        )
        #expect(items == [.window(30), .window(10), .window(20), .app("music"), .app("mail")])
    }

    @Test func unrankedItemsKeepInputOrder() {
        let items = SwitcherOrdering.items(windows: [3, 1, 2], windowRecency: [Int](), windowlessApps: [String](), appRecency: [])
        #expect(items == [.window(3), .window(1), .window(2)])
    }

    @Test func duplicateRecencyEntriesUseFirstOccurrence() {
        let items = SwitcherOrdering.items(windows: [1, 2], windowRecency: [2, 1, 2], windowlessApps: [String](), appRecency: [])
        #expect(items == [.window(2), .window(1)])
    }

    @Test func recencyEntriesMissingFromInputAreIgnored() {
        let items = SwitcherOrdering.items(windows: [1, 2], windowRecency: [7, 2, 8], windowlessApps: ["a"], appRecency: ["z", "a"])
        #expect(items == [.window(2), .window(1), .app("a")])
    }

    @Test func windowsAlwaysPrecedeWindowlessApps() {
        let items = SwitcherOrdering.items(windows: [1], windowRecency: [Int](), windowlessApps: ["b", "a"], appRecency: ["a", "b"])
        #expect(items == [.window(1), .app("a"), .app("b")])
    }

    @Test func emptyInputsProduceNoItems() {
        let items = SwitcherOrdering.items(windows: [Int](), windowRecency: [1, 2], windowlessApps: [String](), appRecency: ["a"])
        #expect(items.isEmpty)
    }

    @Test func unrankedAppsKeepInputOrderAfterRankedOnes() {
        let items = SwitcherOrdering.items(windows: [Int](), windowRecency: [], windowlessApps: ["c", "a", "b", "d"], appRecency: ["d", "a"])
        #expect(items == [.app("d"), .app("a"), .app("c"), .app("b")])
    }
}
