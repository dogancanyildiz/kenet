import Foundation
import GoalTracking
import Testing

@testable import Journal

@MainActor
struct GoalValueChartTests {
    @Test(arguments: [GoalKind.number, .boolean, .milestone])
    func visibility(_ kind: GoalKind) throws {
        let goal = try #require(
            GoalDefinition(id: "sample", key: "sample", name: "Sample", period: .year, kind: kind))
        #expect(GoalValueChart.isShown(for: goal) == (kind == .number))
    }

    @Test(arguments: [false, true])
    func dailyRangeAndTitle(_ accessibility: Bool) throws {
        let goal = try #require(
            GoalDefinition(id: "sample", key: "sample", name: "Sample", period: .day, kind: .number))
        let span = accessibility ? 30 : 90
        #expect(GoalValueChart.span(isAccessibilitySize: accessibility) == span)
        #expect(
            GoalValueChart.title(for: goal, isAccessibilitySize: accessibility)
                == String(localized: "Son \(span) gün"))
    }

    @Test(arguments: [GoalPeriod.week, .year])
    func periodTitle(_ period: GoalPeriod) throws {
        let goal = try #require(
            GoalDefinition(id: "sample", key: "sample", name: "Sample", period: period, kind: .number))
        let expected = period == .week ? String(localized: "Son 12 hafta") : String(localized: "Son 12 ay")
        #expect(GoalValueChart.title(for: goal, isAccessibilitySize: false) == expected)
        #expect(GoalValueChart.title(for: goal, isAccessibilitySize: true) == expected)
    }
}

/// Y axis labels: the target always; 0 and the top only when a label line fits between them and the target.
@MainActor
struct GoalValueChartAxisTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let target, top, domain, gap: Double
        let expected: [Double]
        var testDescription: String { "target \(target), top \(top), gap \(gap)" }
    }

    @Test(arguments: [
        // The top sits 5 of 27 above the target: kept at 15 %, dropped at 25 % (a large type size).
        Case(target: 20, top: 25, domain: 27, gap: 0.15, expected: [0, 20, 25]),
        Case(target: 20, top: 25, domain: 27, gap: 0.25, expected: [0, 20]),
        // The top is the target: one label.
        Case(target: 20, top: 20, domain: 21.6, gap: 0.15, expected: [0, 20]),
        // A small target beside a large top: 0 is dropped, the top stays.
        Case(target: 1, top: 100, domain: 108, gap: 0.15, expected: [1, 100]),
    ])
    func axisValues(_ test: Case) {
        #expect(
            GoalValueChart.axisValues(target: test.target, top: test.top, domain: test.domain, gap: test.gap)
                == test.expected)
    }
}
