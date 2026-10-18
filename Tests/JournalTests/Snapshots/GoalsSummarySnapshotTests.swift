#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// Hedefler, Özetler, Graph (+ seçili düğüm, hedef ayrıntı, oluşturma sheet).
    /// Harita MapKit host çökmesi yüzünden bu kümede yok; pin boyutu `GraphMapTests` ile kilitli.
    enum GoalsSummarySnapshotCase: String, CaseIterable, Sendable, SnapshotCaseConfiguring {
        case goalsLight
        case summariesLight
        case graphLight
        case graphSelected
        /// AX3 keeps the goal chart's reduced range and axis labels (docs/design.md).
        case goalDetailLight, goalDetailAX3
        case goalCreationLight

        var screen: SnapshotScreen {
            switch self {
            case .goalsLight: .goals
            case .summariesLight: .summaries
            case .graphLight: .graph
            case .graphSelected: .graphSelected
            case .goalDetailLight, .goalDetailAX3: .goalDetail
            case .goalCreationLight: .goalCreation
            }
        }

        var colorScheme: SnapshotColorScheme { .light }

        var dynamicType: SnapshotDynamicType { self == .goalDetailAX3 ? .accessibility3 : .medium }

        var increaseContrast: Bool { false }

    }

    @MainActor @Suite("Goals summary snapshots")
    struct GoalsSummarySnapshotTests {
        @Test(arguments: GoalsSummarySnapshotCase.allCases)
        func screen(_ snapshotCase: GoalsSummarySnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            // `SnapshotHost.assert` hides and detaches the host window before returning.
            await SnapshotHost.assert(
                snapshotCase, store: context.store, defaults: context.defaults.defaults)
        }
    }
#endif
