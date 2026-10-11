#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    enum UnlinkedMentionsSnapshotCase: String, CaseIterable, Sendable {
        case light, dark, accessibility3

        var colorScheme: SnapshotColorScheme { self == .dark ? .dark : .light }
        var dynamicType: SnapshotDynamicType { self == .accessibility3 ? .accessibility3 : .medium }

        var canvas: CGSize {
            self == .accessibility3 ? CGSize(width: 390, height: 2960) : CGSize(width: 390, height: 1400)
        }
    }

    @MainActor @Suite("Unlinked mention snapshots", .timeLimit(.minutes(2)))
    struct UnlinkedMentionsSnapshotTests {
        @Test(arguments: UnlinkedMentionsSnapshotCase.allCases)
        func entityPage(_ snapshotCase: UnlinkedMentionsSnapshotCase) async throws {
            let context = try UnlinkedMentionsTestContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let entity = try #require(context.store.content.entities.first { $0.id == "people/Elif.md" })
            let ready = ReadyBox()
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                size: snapshotCase.canvas,
                isReady: { ready.dates && ready.mentions },
                testName: "unlinkedMentions",
                content: {
                    NavigationStack {
                        EntityView(store: context.store, entity: entity)
                    }
                    .environment(IntentNavigation())
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                    .environment(\.openSearch, {})
                    .onPreferenceChange(ImportantDatesReadyKey.self) { ready.dates = $0 }
                    .onPreferenceChange(UnlinkedMentionsReadyKey.self) { ready.mentions = $0 }
                }
            )
        }
    }

    extension UnlinkedMentionsSnapshotTests {
        /// Every row of the expanded list under the notice of a refused link: the at sign marked with
        /// its spelling, and the "also matches another record" and "spelled differently" notes.
        @Test func expandedSectionWithNotice() async throws {
            let context = try UnlinkedMentionsTestContext()
            defer { context.clean() }
            await context.start()
            let entity = try context.elif()
            let model = context.model()
            await model.load(entity)
            let mention = try #require(model.mentions.first { $0.file == "journal/2026-10-09.md" })
            let url = context.root.appendingPathComponent(mention.file)
            try Data("## Events\n- Elif gelmedi. ^older1\n".utf8).write(to: url)
            #expect(await model.link(mention, to: entity) == .stale)
            await SnapshotHost.assertView(
                colorScheme: .light,
                dynamicType: .medium,
                increaseContrast: false,
                named: "light",
                store: context.store,
                size: CGSize(width: 390, height: 1400),
                testName: "expandedSectionWithNotice",
                content: {
                    NavigationStack {
                        List {
                            UnlinkedMentionsSection(model: model, expanded: true)
                        }
                        .listStyle(.plain)
                        .inkPage()
                        .inkPageScrollColumn()
                    }
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                }
            )
        }
    }

    @MainActor private final class ReadyBox {
        var dates = false
        var mentions = false
    }
#endif
