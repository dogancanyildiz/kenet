#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    enum CadenceSnapshotCase: String, CaseIterable, Sendable {
        case editLight
        case insightsLight
        case listLight

        enum Subject: Sendable { case edit, insights, list }

        var subject: Subject {
            switch self {
            case .editLight: .edit
            case .insightsLight: .insights
            case .listLight: .list
            }
        }

        var colorScheme: SnapshotColorScheme { .light }

        var dynamicType: SnapshotDynamicType { .medium }

        var canvas: CGSize {
            let ax = dynamicType == .accessibility3
            switch subject {
            case .edit: return CGSize(width: 390, height: ax ? 1600 : 1100)
            case .insights: return CGSize(width: 390, height: ax ? 1600 : 1100)
            case .list: return CGSize(width: 390, height: ax ? 2200 : 1400)
            }
        }
    }

    @MainActor @Suite("Cadence snapshots")
    struct CadenceSnapshotTests {
        private static let personPath = "people/Vera Lale.md"
        private static let cadenceNow: Date = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = snapshotTimeZone
            return calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 9, minute: 41))!
        }()

        @Test(arguments: CadenceSnapshotCase.allCases)
        func cadence(_ snapshotCase: CadenceSnapshotCase) async throws {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }
            let vault = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/vaults/cadence")
            try FileManager.default.copyItem(at: vault, to: context.root)
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let store = context.store
            let detail = EntityDetailModel(store: store, path: Self.personPath)
            if snapshotCase.subject == .edit {
                await detail.load()
                #expect(detail.personCadence.days == 30)
            }
            let person = try #require(store.content.entities.first { $0.id == Self.personPath })
            // The entity page queries the timeline and the last day the card reads; hosted alone,
            // the test does.
            let timeline = try await store.computeEntityTimeline(for: person.id)
            var lastDay: DaySummary?
            if let last = EntityInsights.lastDay(in: timeline, today: LocalDay.today(at: Self.cadenceNow)) {
                lastDay = try await store.computeDay(on: last)
            }
            let ready = CadenceReadyBox()
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: store,
                size: snapshotCase.canvas,
                clock: Self.cadenceNow,
                isReady: { snapshotCase.subject == .edit || ready.isReady },
                testName: "cadence",
                content: {
                    Self.hosted(
                        snapshotCase.subject, store: store, detail: detail, person: person, timeline: timeline,
                        lastDay: lastDay
                    )
                    .environment(IntentNavigation())
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
                    .environment(\.openSearch, {})
                    .onPreferenceChange(CadenceReadyKey.self) { ready.isReady = $0 }
                }
            )
        }

        @ViewBuilder private static func hosted(
            _ subject: CadenceSnapshotCase.Subject, store: IndexStore, detail: EntityDetailModel,
            person: EntitySummary, timeline: [EntityTimelineDay], lastDay: DaySummary?
        ) -> some View {
            switch subject {
            case .edit:
                EntityEditSheet(store: store, model: detail, entity: person)
            case .insights:
                NavigationStack {
                    List { EntityInsightsCard(store: store, entity: person, timeline: timeline, lastDay: lastDay) }
                        .listStyle(.plain)
                        .inkPage()
                }
            case .list:
                NavigationStack {
                    List {
                        UnseenPeopleSection(
                            store: store, people: store.content.entities, initiallyExpanded: true)
                    }
                    .listStyle(.plain)
                    .inkPage()
                }
            }
        }
    }

    private final class CadenceReadyBox {
        var isReady = false
    }
#endif
