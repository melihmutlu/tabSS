import Testing
@testable import TabssCore

struct WindowRegistryTests {
    private var registry = WindowRegistry<Int, String>(zOrder: [900, 30, 10, 20])

    @Test mutating func seededZOrderIsKeptAndUnseenWindowsRankLast() {
        for (window, app) in [(10, "a"), (40, "b"), (20, "a"), (30, "c")] {
            registry.add(window, of: app)
        }
        #expect(registry.items(runningApps: []) == [.window(30), .window(10), .window(20), .window(40)])
    }

    @Test mutating func focusOrderIsMostRecentFirst() {
        for window in [10, 20, 30] { registry.add(window, of: "a") }
        for window in [10, 20, 30] { registry.focus(window) }
        #expect(registry.items(runningApps: []) == [.window(30), .window(20), .window(10)])
    }

    @Test mutating func focusReportsTheWindowThatLostIt() {
        registry.add(10, of: "a")
        registry.add(20, of: "a")
        let lostFocus = [registry.focus(10), registry.focus(10), registry.focus(20), registry.focus(nil)]
        #expect(lostFocus == [nil, nil, 10, 20])
        #expect(registry.focusedWindow == nil)
    }

    @Test mutating func removingAWindowClearsItsFocus() {
        registry.add(10, of: "a")
        registry.focus(10)
        registry.remove(10)
        #expect(registry.focusedWindow == nil)
        #expect(registry.owner(of: 10) == nil)
        #expect(registry.items(runningApps: []).isEmpty)
    }

    @Test mutating func removingAnAppRemovesItsWindowsAndRecency() {
        registry.add(10, of: "a")
        registry.add(20, of: "b")
        registry.add(30, of: "a")
        registry.activate("a", focusedWindow: 30)
        let removed = registry.removeApp("a")
        #expect(Set(removed) == [10, 30])
        #expect(registry.focusedWindow == nil)
        #expect(registry.items(runningApps: ["b", "a"]) == [.window(20), .app("a")])
    }

    @Test mutating func windowlessAppsFollowWindowsByActivationRecency() {
        registry.add(10, of: "a")
        registry.activate("mail", focusedWindow: nil)
        registry.activate("a", focusedWindow: 10)
        registry.activate("music", focusedWindow: nil)
        #expect(registry.items(runningApps: ["a", "mail", "music", "notes"]) == [.window(10), .app("music"), .app("mail"), .app("notes")])
    }

    @Test mutating func focusMovingToANonSwitchableWindowKeepsTheLastWindowFirst() {
        for window in [10, 20] { registry.add(window, of: "a") }
        registry.focus(10)
        registry.focus(20)
        #expect(registry.focus(nil) == 20)
        #expect(registry.items(runningApps: ["a"]) == [.window(20), .window(10)])
    }

    @Test mutating func reAddedWindowRanksLastInsteadOfReclaimingItsSeat() {
        for window in [10, 20, 30] { registry.add(window, of: "a") }
        registry.remove(30)
        registry.add(30, of: "a")
        #expect(registry.items(runningApps: []) == [.window(10), .window(20), .window(30)])
    }

    @Test mutating func appWhoseLastWindowClosesBecomesAWindowlessItem() {
        registry.add(10, of: "a")
        registry.add(20, of: "b")
        registry.activate("b", focusedWindow: 20)
        registry.activate("a", focusedWindow: 10)
        registry.remove(10)
        #expect(registry.focusedWindow == nil)
        #expect(registry.items(runningApps: ["b", "a"]) == [.window(20), .app("a")])
    }

    @Test mutating func activatingWithUnchangedFocusStillRanksTheApp() {
        registry.activate("a", focusedWindow: nil)
        registry.activate("b", focusedWindow: nil)
        #expect(registry.activate("a", focusedWindow: nil) == nil)
        #expect(registry.items(runningApps: ["b", "a"]) == [.app("a"), .app("b")])
    }

    @Test mutating func removingUnknownWindowsOrAppsLeavesFocusAlone() {
        registry.add(10, of: "a")
        registry.focus(10)
        registry.remove(99)
        #expect(registry.removeApp("zzz").isEmpty)
        #expect(registry.focusedWindow == 10)
        #expect(registry.items(runningApps: ["a"]) == [.window(10)])
    }

    @Test mutating func addingTwiceKeepsTheFirstOwner() {
        let added = [registry.add(10, of: "a"), registry.add(10, of: "b")]
        #expect(added == [true, false])
        #expect(registry.windows(of: "a") == [10])
        #expect(registry.windows(of: "b").isEmpty)
    }

    @Test mutating func activatingAnotherAppReportsThePreviousAppsWindow() {
        registry.add(10, of: "a")
        registry.add(20, of: "b")
        registry.activate("a", focusedWindow: 10)
        let lostFocus = registry.activate("b", focusedWindow: 20)
        #expect(lostFocus == 10)
    }

    @Test mutating func removingAnUnfocusedWindowKeepsFocus() {
        registry.add(10, of: "a")
        registry.add(20, of: "a")
        registry.focus(10)
        registry.remove(20)
        #expect(registry.focusedWindow == 10)
    }

    // Startup: the frontmost app's focused window outranks the seeded z-order.
    @Test mutating func startupFocusSyncOverridesSeededOrder() {
        for (window, app) in [(30, "c"), (10, "a"), (20, "a")] { registry.add(window, of: app) }
        #expect(registry.activate("a", focusedWindow: 20) == nil)
        #expect(registry.items(runningApps: ["a", "c"]) == [.window(20), .window(30), .window(10)])
    }

    @Test mutating func focusAcrossThreeAppsReportsEachDepartureAndOrdersByRecency() {
        for (window, app) in [(10, "a"), (20, "b"), (30, "c")] { registry.add(window, of: app) }
        let lostFocus = [
            registry.activate("a", focusedWindow: 10),
            registry.activate("b", focusedWindow: 20),
            registry.activate("c", focusedWindow: 30),
        ]
        #expect(lostFocus == [nil, 10, 20])
        #expect(registry.items(runningApps: ["a", "b", "c"]) == [.window(30), .window(20), .window(10)])
    }

    @Test mutating func activatingAWindowlessAppReportsThePreviousWindowAndClearsFocus() {
        registry.add(10, of: "a")
        registry.activate("a", focusedWindow: 10)
        #expect(registry.activate("mail", focusedWindow: nil) == 10)
        #expect(registry.focusedWindow == nil)
        #expect(registry.items(runningApps: ["a", "mail"]) == [.window(10), .app("mail")])
    }

    // A window first rejected (focus went to nil), then accepted on recheck and re-synced, becomes most recent.
    @Test mutating func windowAcceptedOnRecheckTakesFocusAndLeadsWhenResynced() {
        for window in [10, 20] { registry.add(window, of: "a") }
        registry.activate("a", focusedWindow: 10)
        #expect(registry.focus(nil) == 10)
        registry.add(55, of: "a")
        #expect(registry.activate("a", focusedWindow: 55) == nil)
        #expect(registry.focusedWindow == 55)
        #expect(registry.items(runningApps: ["a"]) == [.window(55), .window(10), .window(20)])
    }

    // A pruned focused window must not be reported as losing focus later.
    @Test mutating func removedFocusedWindowIsNotReportedOnNextActivation() {
        registry.add(10, of: "a")
        registry.add(20, of: "b")
        registry.activate("a", focusedWindow: 10)
        registry.remove(10)
        #expect(registry.activate("b", focusedWindow: 20) == nil)
        #expect(registry.items(runningApps: ["a", "b"]) == [.window(20), .app("a")])
    }

    @Test mutating func terminatedAppDisappearsFromItemsAndRecency() {
        registry.add(10, of: "a")
        registry.activate("a", focusedWindow: 10)
        registry.activate("b", focusedWindow: nil)
        #expect(registry.removeApp("a") == [10])
        // If the pid were reused by a relaunch, it starts unranked.
        #expect(registry.items(runningApps: ["c", "a", "b"]) == [.app("b"), .app("c"), .app("a")])
    }

    @Test mutating func focusingAnUnknownWindowClearsFocusWithoutRankingIt() {
        registry.add(10, of: "a")
        registry.focus(10)
        let lostFocus = registry.focus(99)
        #expect(lostFocus == 10)
        #expect(registry.focusedWindow == nil)
        #expect(registry.items(runningApps: []) == [.window(10)])
    }

    @Test mutating func ownerIsTheAppThatAddedTheWindowUntilItIsRemoved() {
        registry.add(10, of: "a")
        registry.add(20, of: "b")
        #expect([registry.owner(of: 10), registry.owner(of: 20), registry.owner(of: 99)] == ["a", "b", nil])
        _ = registry.removeApp("a")
        #expect(registry.owner(of: 10) == nil)
        #expect(registry.owner(of: 20) == "b")
    }

    // A late focus event carrying a pruned window's ID must not hand it a recency seat it keeps when re-added.
    @Test mutating func activatingWithAStaleWindowRanksTheAppButNotTheWindow() {
        for window in [10, 20, 30] { registry.add(window, of: "a") }
        registry.focus(10)
        registry.remove(30)
        #expect(registry.activate("a", focusedWindow: 30) == 10)
        #expect(registry.focusedWindow == nil)
        registry.add(30, of: "a")
        #expect(registry.items(runningApps: ["a"]) == [.window(10), .window(20), .window(30)])
    }
}
