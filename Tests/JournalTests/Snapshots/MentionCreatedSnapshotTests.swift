#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// Hızlı giriş, yazarken oluşturulan kişiden sonra: taslak yerinde, şeritte tek satır onay (açık, koyu, AX3).
    enum MentionCreatedSnapshotCase: String, CaseIterable, Sendable {
        case mentionCreatedLight
        case mentionCreatedDark
        case mentionCreatedAX3

        var colorScheme: SnapshotColorScheme { self == .mentionCreatedDark ? .dark : .light }
        var dynamicType: SnapshotDynamicType { self == .mentionCreatedAX3 ? .accessibility3 : .medium }
    }

    @MainActor @Suite("Mention created snapshots")
    struct MentionCreatedSnapshotTests {
        /// The bar right after "Yeni kişi oluştur": the draft is not sent and the strip confirms the creation.
        @Test(arguments: MentionCreatedSnapshotCase.allCases)
        func mentionCreated(_ snapshotCase: MentionCreatedSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            let store = context.store
            let model = QuickEntryModel(store: store, today: { snapshotDay }, now: { snapshotNow })
            model.languages = [.turkish, .english]
            model.text = "Bugün @Yeni Ad"
            #expect(await model.composer.beginCreation(.person) == .keepEditing)
            #expect(model.composer.creationNotice != nil)
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
                            .padding(.bottom, 16)
                    }
                    .environment(location)
                    .environment(\.mentionNoticeLifetime, nil)
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                }
            )
        }
    }
#endif
