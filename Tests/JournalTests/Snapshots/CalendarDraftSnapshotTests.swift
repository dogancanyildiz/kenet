#if os(iOS)
    import EntityRecognition
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Hızlı giriş, takvim etkinliğinden düşmüş taslakla: açık tema.
    enum CalendarDraftSnapshotCase: String, CaseIterable, Sendable {
        case calendarDraftLight

        var colorScheme: SnapshotColorScheme { .light }
        var dynamicType: SnapshotDynamicType { .medium }
    }

    @MainActor @Suite("Calendar draft snapshots")
    struct CalendarDraftSnapshotTests {
        /// The bar alone, as it sits above the keyboard: the event's start in the time control,
        /// the known attendees in the text and the unknown ones as chips above it.
        @Test(arguments: CalendarDraftSnapshotCase.allCases)
        func calendarDraft(_ snapshotCase: CalendarDraftSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let model = QuickEntryModel(store: store, today: { snapshotDay }, now: { snapshotNow })
            model.languages = [.turkish, .english]
            var event = CalendarEvent(
                id: "meeting", title: "Proje toplantısı", start: snapshotNow.addingTimeInterval(5 * 3600 - 11 * 60),
                end: snapshotNow.addingTimeInterval(6 * 3600), isAllDay: false,
                color: CalendarEventColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            event.attendees = [
                Attendee(name: "Deniz Arıkan"), Attendee(name: "Ada Soylu"), Attendee(name: "Kerem Aydın"),
                Attendee(name: "Selin Korkmaz", isCurrentUser: true),
            ]
            #expect(model.applyCalendarDraft(event, timeZone: snapshotTimeZone))
            #expect(model.unknownAttendees == ["Ada Soylu", "Kerem Aydın"])
            let location = LocationService(source: FakeLocationSource(), defaults: context.defaults.defaults)
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                size: CGSize(width: 390, height: snapshotCase.dynamicType == .medium ? 200 : 320),
                testName: "quickEntry",
                file: #filePath,
                line: #line,
                content: {
                    // Placed as on the day page; a plain stack would offer the bar half the canvas.
                    Color.ink.paper.safeAreaInset(edge: .bottom, spacing: 0) {
                        QuickEntryBar(store: store, isEnabled: true, model: model)
                            // The host centres this short canvas between unequal safe areas;
                            // keep the capsule clear of the edge that shift would cut.
                            .padding(.bottom, 16)
                    }
                    .environment(location)
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                }
            )
        }
    }
#endif
