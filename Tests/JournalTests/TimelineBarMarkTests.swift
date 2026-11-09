import Testing
import VaultFormat

@testable import Journal

@Suite struct TimelineBarMarkTests {
    @Test func oneDaySpanUsesCircleAndLongSpanUsesCapsule() {
        let single = TimelineDates(start: CalendarDate("2026-09-20"), due: CalendarDate("2026-09-20"))
            .span(on: CalendarDate("2026-09-20")!)!
        let range = TimelineDates(start: CalendarDate("2026-09-20"), due: CalendarDate("2026-09-22"))
            .span(on: CalendarDate("2026-09-20")!)!
        #expect(TimelineBarMark.choice(for: single) == .circle)
        #expect(TimelineBarMark.choice(for: range) == .capsule)
    }
}
