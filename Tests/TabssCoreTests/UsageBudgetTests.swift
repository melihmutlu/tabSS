import Testing
@testable import TabssCore

struct UsageBudgetTests {
    private let start = ContinuousClock.now
    private var budget = UsageBudget(limit: .milliseconds(300), per: .seconds(1))

    @Test mutating func manySmallCostsAddUpWithinTheWindow() {
        let results = (0..<4).map { budget.charge(.milliseconds(90), at: start + .milliseconds(100 * $0)) }
        #expect(results == [false, false, false, true])
    }

    @Test mutating func aNewWindowStartsFresh() {
        _ = budget.charge(.milliseconds(250), at: start)
        let afterWindow = budget.charge(.milliseconds(250), at: start + .seconds(1))
        #expect(!afterWindow)
    }

    @Test mutating func oneLargeCostIsOverAtOnce() {
        let over = budget.charge(.milliseconds(301), at: start)
        #expect(over)
    }

    @Test mutating func exactlyTheLimitIsAllowed() {
        let atLimit = budget.charge(.milliseconds(300), at: start)
        #expect(!atLimit)
    }
}
