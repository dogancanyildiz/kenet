import Foundation
import Testing
import VaultFormat

@testable import Journal

/// The weekly review's mini rhythm against vault files: it follows the device calendar's week,
/// adds up to the numbers step, and the previous week compares with the week before it.
/// Saturday 3 October 2026 is the review day.
@MainActor
struct WeeklyReviewRhythmModelTests {
    private static let files: [String: String] = [
        "journal/2026-09-20.md": "## Events\n- 08:00 koşu ^e1\n",
        "journal/2026-09-27.md": "## Events\n- 11:00 pazar kahvaltısı ^e2\n",
        "journal/2026-09-28.md": "## Events\n- 09:00 toplantı ^e3\n- 13:00 öğle yemeği ^e4\n",
        "journal/2026-09-30.md": "## Journal\nSakin bir gün.\n",
        "journal/2026-10-03.md": "## Events\n- 09:00 yürüyüş ^e5\n",
        "journal/2026-10-04.md": "## Events\n- 10:00 gelecek gün ^e6\n- 12:00 gelecek öğle ^e7\n",
    ]

    private static let turkish = Locale(identifier: "tr_TR")

    private func model(firstWeekday: Int, _ context: TaskTestContext) async -> WeeklyReviewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let model = WeeklyReviewModel(
            store: context.store, today: context.today, calendar: calendar, locale: Self.turkish,
            defaults: context.defaults.defaults)
        await model.load()
        return model
    }

    private func context() async throws -> TaskTestContext {
        let context = try TaskTestContext()
        await context.start()
        for (path, text) in Self.files {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        await context.store.refresh()
        return context
    }

    private var bundle: Bundle { PresentationLocalization.bundle(Self.turkish) }

    @Test func sundayWeekEndsOnTheReviewDay() async throws {
        let context = try await context()
        defer { context.clean() }
        let model = await model(firstWeekday: 1, context)
        let items = model.rhythmItems
        #expect(model.range == CalendarDate("2026-09-27")!...CalendarDate("2026-10-03")!)
        #expect(items.map(\.value) == [1, 2, 0, 0, 0, 0, 1])
        #expect(items.map(\.previous) == [1, 0, 0, 0, 0, 0, 0])
        #expect(items.map(\.mark) == [.full, .full, .none, .full, .none, .none, .full])
        #expect(items.map(\.value).reduce(0, +) == model.content?.events)
        let signed = SummaryPresentation.signed(3, locale: Self.turkish)
        #expect(
            model.rhythmChange
                == String(localized: "Önceki haftaya göre \(signed) olay", bundle: bundle, locale: Self.turkish))
    }

    @Test func runningMondayWeekComparesToTheSameWeekday() async throws {
        let context = try await context()
        defer { context.clean() }
        let model = await model(firstWeekday: 2, context)
        let items = model.rhythmItems
        // Sunday 4 October has not come: its file counts neither in the bar nor in the change.
        #expect(items.map(\.value) == [2, 0, 0, 0, 0, 1, 0])
        #expect(items.last?.mark == .notStarted)
        // The numbers step counts every day file of the week, the future-dated one too: the strip
        // and the change stop at today, so they read 3 where "Olay sayısı" reads 5.
        #expect(items.map(\.value).reduce(0, +) == 3)
        #expect(model.content?.events == 5)
        // The Sunday before stands behind the coming Sunday, outside the change.
        #expect(items.map(\.previous) == [0, 0, 0, 0, 0, 0, 1])
        let signed = SummaryPresentation.signed(3, locale: Self.turkish)
        #expect(
            model.rhythmChange
                == String(
                    localized: "Geçen haftanın aynı gününe göre \(signed) olay", bundle: bundle,
                    locale: Self.turkish))
    }

    /// The previous week's strip needs the week before it, which the counts never read.
    @Test func previousWeekComparesWithTheWeekBeforeIt() async throws {
        let context = try await context()
        defer { context.clean() }
        let model = await model(firstWeekday: 2, context)
        let current = model.content
        model.week = .previous
        #expect(model.range == CalendarDate("2026-09-21")!...CalendarDate("2026-09-27")!)
        #expect(model.rhythmItems.map(\.value) == [0, 0, 0, 0, 0, 0, 1])
        #expect(model.rhythmItems.map(\.previous) == [0, 0, 0, 0, 0, 0, 1])
        #expect(model.content?.events == 1)
        #expect(
            model.rhythmChange
                == String(localized: "Önceki haftayla aynı sayıda olay", bundle: bundle, locale: Self.turkish))
        model.week = .current
        #expect(model.content == current)
    }
}
