import Testing
import VaultFormat

@testable import Journal

struct TaskStatusPresentationTests {
    @Test func openPastDueShowsOverdueCueWithoutOpacity() throws {
        let due = try #require(CalendarDate("2026-09-20"))
        let day = try #require(CalendarDate("2026-10-05"))
        let presentation = TaskStatusPresentation.make(due: due, asOf: day, isCompleted: false)
        #expect(presentation.showsOverdueCue)
        #expect(!presentation.usesSecondaryText)
        #expect(presentation.opacity == 1)
    }

    @Test func completedPastDueHidesOverdueCueAndKeepsReadableText() throws {
        let due = try #require(CalendarDate("2026-09-20"))
        let day = try #require(CalendarDate("2026-10-05"))
        let presentation = TaskStatusPresentation.make(due: due, asOf: day, isCompleted: true)
        #expect(!presentation.showsOverdueCue)
        #expect(presentation.usesSecondaryText)
        #expect(presentation.opacity == 1)
    }

    @Test func futureDueShowsNoOverdueCue() throws {
        let due = try #require(CalendarDate("2026-10-12"))
        let day = try #require(CalendarDate("2026-10-05"))
        let open = TaskStatusPresentation.make(due: due, asOf: day, isCompleted: false)
        #expect(!open.showsOverdueCue)
        #expect(!open.usesSecondaryText)
        #expect(open.opacity == 1)
        let done = TaskStatusPresentation.make(due: due, asOf: day, isCompleted: true)
        #expect(!done.showsOverdueCue)
        #expect(done.usesSecondaryText)
        #expect(done.opacity == 1)
    }

    @Test func undatedNeverShowsOverdueCue() throws {
        let day = try #require(CalendarDate("2026-10-05"))
        let open = TaskStatusPresentation.make(due: nil, asOf: day, isCompleted: false)
        #expect(!open.showsOverdueCue)
        #expect(open.opacity == 1)
        let done = TaskStatusPresentation.make(due: nil, asOf: day, isCompleted: true)
        #expect(!done.showsOverdueCue)
        #expect(done.usesSecondaryText)
        #expect(done.opacity == 1)
    }
}
