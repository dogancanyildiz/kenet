import Testing
import VaultFormat

@testable import Kenet

@Suite struct TimelineBarMarkTests {
    private let day = CalendarDate("2026-09-20")!

    @Test func dueOnlyTaskIsARoundBadge() {
        let span = TimelineDates(start: nil, due: CalendarDate("2026-09-20")).span(on: day)!
        #expect(TimelineBarMark.choice(for: span) == .circle)
    }

    @Test func rangeIsACapsule() {
        let span = TimelineDates(start: CalendarDate("2026-09-20"), due: CalendarDate("2026-09-22"))
            .span(on: day)!
        #expect(TimelineBarMark.choice(for: span) == .capsule)
    }

    /// Same-day start and due stay a bar: the grips that change its dates stay on it.
    @Test func sameDayStartAndDueKeepsTheBar() {
        let span = TimelineDates(start: CalendarDate("2026-09-20"), due: CalendarDate("2026-09-20"))
            .span(on: day)!
        #expect(TimelineBarMark.choice(for: span) == .capsule)
    }
}
