import Testing
@testable import TabssCore

struct SwitcherOrderingTests {
    @Test func windowsKeepRecencyOrderThenWindowlessAppsByRecency() {
        let items = SwitcherOrdering.items(windowsByRecency: [30, 10, 20], windowlessApps: ["mail", "music"], appRecency: ["music"])
        #expect(items == [.window(30), .window(10), .window(20), .app("music"), .app("mail")])
    }

    @Test func unrankedAppsKeepInputOrderAfterRankedOnes() {
        let items = SwitcherOrdering.items(windowsByRecency: [Int](), windowlessApps: ["c", "a", "b", "d"], appRecency: ["d", "a"])
        #expect(items == [.app("d"), .app("a"), .app("c"), .app("b")])
    }

    @Test func recencyEntriesThatAreNotWindowlessAreIgnored() {
        let items = SwitcherOrdering.items(windowsByRecency: [1], windowlessApps: ["a"], appRecency: ["z", "a", "a"])
        #expect(items == [.window(1), .app("a")])
    }

    @Test func emptyInputsProduceNoItems() {
        #expect(SwitcherOrdering.items(windowsByRecency: [Int](), windowlessApps: [String](), appRecency: ["a"]).isEmpty)
    }
}
