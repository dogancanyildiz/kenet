#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Hızlı giriş, görev kipi: tanınan ifadelerin çipleri (açık, koyu, AX3) ve biri geri alınmış hali.
    enum QuickEntryChipSnapshotCase: String, CaseIterable, Sendable {
        case quickEntryChipsLight
        case quickEntryChipsDark
        case quickEntryChipsAX3
        case quickEntryChipsUndone

        var colorScheme: SnapshotColorScheme { self == .quickEntryChipsDark ? .dark : .light }
        var dynamicType: SnapshotDynamicType { self == .quickEntryChipsAX3 ? .accessibility3 : .medium }
    }

    @MainActor @Suite("Quick entry chips snapshots")
    struct QuickEntryChipsSnapshotTests {
        /// The bar alone, as it sits above the keyboard: date control and chips share one row.
        @Test(arguments: QuickEntryChipSnapshotCase.allCases)
        func quickEntryChips(_ snapshotCase: QuickEntryChipSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let model = QuickEntryModel(store: store, today: { snapshotDay }, now: { snapshotNow })
            model.languages = [.turkish, .english]
            model.mode = .task
            model.text = "!! yarın Deniz'i ara her hafta"
            if snapshotCase == .quickEntryChipsUndone {
                model.undoRecognition(try #require(model.taskExpressions.first { $0.spelling == "yarın" }))
            }
            let location = LocationService(source: FakeLocationSource(), defaults: context.defaults.defaults)
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                size: CGSize(width: 390, height: snapshotCase.dynamicType == .medium ? 200 : 320),
                testName: "today",
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
