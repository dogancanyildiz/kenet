#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Hedefler, Özetler, Graph (+ seçili düğüm, hedef ayrıntı, oluşturma sheet).
    /// Harita MapKit host çökmesi yüzünden bu kümede yok; pin boyutu `GraphMapTests` ile kilitli.
    enum GoalsSummarySnapshotCase: String, CaseIterable, Sendable, SnapshotCaseConfiguring {
        case goalsLight, goalsDark, goalsAX3, goalsContrast
        case summariesLight, summariesDark, summariesAX3, summariesContrast
        case graphLight, graphDark, graphAX3, graphContrast
        case graphSelected
        case goalDetailDarkAX3Contrast
        case goalCreationLight, goalCreationAX3

        var screen: SnapshotScreen {
            switch self {
            case .goalsLight, .goalsDark, .goalsAX3, .goalsContrast: .goals
            case .summariesLight, .summariesDark, .summariesAX3, .summariesContrast: .summaries
            case .graphLight, .graphDark, .graphAX3, .graphContrast: .graph
            case .graphSelected: .graphSelected
            case .goalDetailDarkAX3Contrast: .goalDetail
            case .goalCreationLight, .goalCreationAX3: .goalCreation
            }
        }

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .goalsDark, .summariesDark, .graphDark, .goalDetailDarkAX3Contrast: .dark
            default: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .goalsAX3, .summariesAX3, .graphAX3, .goalDetailDarkAX3Contrast, .goalCreationAX3:
                .accessibility3
            default: .medium
            }
        }

        var increaseContrast: Bool {
            switch self {
            case .goalsContrast, .summariesContrast, .graphContrast, .goalDetailDarkAX3Contrast:
                true
            default: false
            }
        }
    }

    @MainActor @Suite("Goals summary snapshots")
    struct GoalsSummarySnapshotTests {
        @Test(arguments: GoalsSummarySnapshotCase.allCases)
        func screen(_ snapshotCase: GoalsSummarySnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            await SnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults)
        }
    }
#endif
