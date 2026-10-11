import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Quick entry and the headless intents hand bare text to the recognizer: no list marker, no clock.
/// A place named `12` is linked there only where the user wrote `@12`; every other number stays as typed.
@MainActor
struct DigitNameWritePathTests {
    private let instant = notificationDate("2026-10-04", hour: 12)

    private func context() throws -> TaskTestContext {
        let context = try TaskTestContext(sample: true)
        for name in ["12", "30", "2026", "10", "1", "34"] {
            try Data("---\ntype: place\nname: \(name)\n---\n".utf8)
                .write(to: context.root.appendingPathComponent("places/\(name).md"))
        }
        return context
    }

    private func document(_ context: TaskTestContext, on day: CalendarDate) throws -> RawDocument {
        RawDocument(bytes: try Data(contentsOf: context.root.appendingPathComponent("journal/\(day).md")))
    }

    @Test func quickEntryEventLinksADigitNameOnlyAfterAnAtSign() async throws {
        let context = try context()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.text = "saat 12:30'da toplantı, 12 Ekim 2026 için 12 kişi, 34 plakalı araçla @12"
        #expect(await model.submit(time: try LineClock(hour: 13, minute: 0)))
        let event = try #require(try document(context, on: LocalDay.today()).bodyLines.events.last)
        #expect(event.block.text == "saat 12:30'da toplantı, 12 Ekim 2026 için 12 kişi, 34 plakalı araçla [[12]]")
        #expect(event.time?.raw == "13:00")
    }

    @Test func quickEntryTaskLinksADigitNameOnlyAfterAnAtSign() async throws {
        let context = try context()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarın 12:30 ara, 12 kişi, @12 de"
        #expect(await model.submit(time: nil))
        let task = try #require(try context.document().bodyLines.tasks.first)
        #expect(task.text == "12:30 ara, 12 kişi, [[12]] de")
        #expect(task.dueDate == context.today.addingDays(1))
    }

    @Test func intentEventLinksADigitNameOnlyAfterAnAtSign() async throws {
        let context = try context()
        defer { context.clean() }
        let date = instant
        let actions = IntentActions(store: context.store, now: { date }, permitsStart: { true })
        _ = try await actions.addEvent(
            text: "saat 12:30'da toplantı, 1. Elma, 12 kişi ve @12", time: try LineClock(hour: 13, minute: 0))
        let event = try #require(try document(context, on: LocalDay.today(at: instant)).bodyLines.events.first)
        #expect(event.block.text == "saat 12:30'da toplantı, 1. Elma, 12 kişi ve [[12]]")
        #expect(event.time?.raw == "13:00")
    }

    @Test func intentTaskLinksADigitNameOnlyAfterAnAtSign() async throws {
        let context = try context()
        defer { context.clean() }
        let date = instant
        let actions = IntentActions(store: context.store, now: { date }, permitsStart: { true })
        _ = try await actions.addTask(text: "yarın 12:30 ara, 12 kişi, @12 de")
        let day = LocalDay.today(at: instant)
        let task = try #require(try document(context, on: day).bodyLines.tasks.first)
        #expect(task.text == "12:30 ara, 12 kişi, [[12]] de")
        #expect(task.dueDate == day.addingDays(1))
    }
}
