#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Hızlı giriş ve sistemin günlük önerileri: düğme olan iPhone, düğme olmayan cihaz (iPad, yetki
    /// ya da çerçeve yok) ve seçimden sonra dünün anı: not bandında gün, sıradaki satır ve fotoğraf
    /// notu, kasanın tanımadığı konum çipi; aynısı en büyük erişilebilirlik boyutlarından birinde.
    enum JournalingSuggestionsSnapshotCase: String, CaseIterable, Sendable {
        case suggestionsButton
        case suggestionsUnavailable
        case suggestionsQueued
        case suggestionsQueuedAX3

        var isAvailable: Bool { self != .suggestionsUnavailable }
        var isQueued: Bool { self == .suggestionsQueued || self == .suggestionsQueuedAX3 }
        var dynamicType: SnapshotDynamicType { self == .suggestionsQueuedAX3 ? .accessibility3 : .medium }
    }

    @MainActor @Suite("Journaling suggestions snapshots")
    struct JournalingSuggestionsSnapshotTests {
        /// The bar alone, as it sits above the keyboard. The simulator has no framework, so the
        /// environment says whether the device offers the picker.
        @Test(arguments: JournalingSuggestionsSnapshotCase.allCases)
        func journalingSuggestions(_ snapshotCase: JournalingSuggestionsSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let model = QuickEntryModel(store: store, today: { snapshotDay }, now: { snapshotNow })
            model.languages = [.turkish, .english]
            if snapshotCase.isQueued {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = snapshotTimeZone
                let yesterday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 7, minute: 40))
                let pick = SuggestionPick(
                    title: "Cumartesi", date: nil,
                    items: [
                        .workout(name: "Koşu", duration: 32 * 60, start: yesterday),
                        .location(name: "Moda Sahili", city: nil, date: nil),
                        .attachment(.photo),
                        .song(title: "Yol", artist: "Grup Mavi", date: nil),
                    ])
                #expect(model.applySuggestion(pick, locale: snapshotLocale, timeZone: snapshotTimeZone))
            }
            let location = LocationService(source: FakeLocationSource(), defaults: context.defaults.defaults)
            await SnapshotHost.assertView(
                colorScheme: .light,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                size: CGSize(width: 390, height: snapshotCase == .suggestionsQueuedAX3 ? 420 : 200),
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
                    .environment(\.journalingSuggestionsAvailable, snapshotCase.isAvailable)
                }
            )
        }
    }
#endif
