#if os(iOS)
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Sheets over the iPad shell on the 13-inch in landscape, light and AX3: Ayarlar (the Today
    /// manşet's gear, through the real `AdaptiveNavigation`), Ara (the system sheet `ContentView`
    /// presents above the shell), Günü kapat (the evening reminder's route on Today) and the
    /// task detail a board narrower than its panel threshold presents.
    enum PadSheetCase: String, CaseIterable, Sendable {
        case settingsLight, settingsAX3
        case searchLight, searchAX3
        case closeDayLight, closeDayAX3
        case taskDetailLight, taskDetailAX3

        enum Sheet: Sendable { case settings, search, closeDay, taskDetail }

        var sheet: Sheet {
            switch self {
            case .settingsLight, .settingsAX3: .settings
            case .searchLight, .searchAX3: .search
            case .closeDayLight, .closeDayAX3: .closeDay
            case .taskDetailLight, .taskDetailAX3: .taskDetail
            }
        }

        /// Search is hosted but not drawn: its field takes focus and the simulator keyboard moves
        /// the system sheet, so two runs differ (as in `ChromeSheetsDuoSnapshotTests`). The
        /// hosted case still checks that the sheet is up with its field on screen.
        var isDrawn: Bool { sheet != .search }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .settingsAX3, .searchAX3, .closeDayAX3, .taskDetailAX3: .accessibility3
            default: .medium
            }
        }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadSheetSnapshotTests {
        @Test(arguments: PadSheetCase.allCases)
        func sheet(_ snapshotCase: PadSheetCase) async throws {
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "sheet", canvas: .pad13Landscape,
                dynamicType: snapshotCase.dynamicType, presentsSheet: true,
                shellKind: snapshotCase.sheet == .taskDetail ? .split : nil,
                masks: snapshotCase.sheet == .taskDetail ? [] : [PadSnapshotHost.Mask.sidebarButton],
                inspect: Self.checkSheet(snapshotCase),
                draws: snapshotCase.isDrawn
            ) { scene in
                let store = scene.store
                switch snapshotCase.sheet {
                case .settings:
                    return AnyView(AdaptiveNavigation(store: store, showsSettings: true))
                case .search:
                    return AnyView(PadSearchSheetContent(store: store))
                case .closeDay:
                    // The evening reminder's route: Today opens its close-day sheet on the journal step.
                    scene.notifications.open(.journal)
                    return AnyView(AdaptiveNavigation(store: store))
                case .taskDetail:
                    let tasks = TasksModel(store: store, today: { snapshotDay })
                    tasks.section = .kanban
                    let row = try #require(try await store.allTasks().first { !$0.isClosed })
                    // Narrower than the panel threshold: the board presents its own sheet.
                    return AnyView(
                        NavigationStack { KanbanView(tasks: tasks, showsFilters: true, selection: row) }
                            .frame(width: 600)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .inkPage())
                }
            }
        }
    }

    extension PadSheetSnapshotTests {
        /// The presented sheet is tall enough and shows a row or an input.
        static func checkSheet(_ snapshotCase: PadSheetCase) -> @MainActor (UIHostingController<AnyView>) -> Void {
            { host in
                let sheet = host.presentedViewController
                #expect((sheet?.view.bounds.height ?? 0) >= 360, "\(snapshotCase): sheet too short")
                #expect(
                    sheet.map { ChromeSheetsDuoHost.hasVisibleRowOrField(in: $0.view) } ?? false,
                    "\(snapshotCase): the sheet must contain a visible row or input.")
            }
        }
    }

    /// Search is the one sheet presented above the shell (`ContentView`), as in production.
    private struct PadSearchSheetContent: View {
        let store: IndexStore
        @State private var presentsSearch = false

        var body: some View {
            AdaptiveNavigation(store: store)
                .onAppear { presentsSearch = true }
                .sheet(isPresented: $presentsSearch) { SearchView(store: store) }
        }
    }
#endif
