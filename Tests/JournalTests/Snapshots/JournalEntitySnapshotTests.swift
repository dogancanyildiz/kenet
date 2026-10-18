#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Günlük listesi, varlık okuma sayfası ve arama: açık tema.
    @MainActor @Suite("Journal entity snapshots", .serialized)
    struct JournalEntitySnapshotTests {
        enum Case: String, CaseIterable, Sendable, SnapshotCaseConfiguring {
            case daysLight, daysSelected
            case entityLight
            case searchLight

            var screen: SnapshotScreen {
                switch self {
                case .daysLight: .days
                case .daysSelected: .daysSelected
                case .entityLight: .entity
                case .searchLight: .search
                }
            }

            var colorScheme: SnapshotColorScheme { .light }

            var dynamicType: SnapshotDynamicType { .medium }

            var increaseContrast: Bool { false }
        }

        @Test func entityScreens() async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.lastUpdated != nil)
            let filter = ProcessInfo.processInfo.environment["SNAPSHOT_ONLY"]
                .map { Set($0.split(separator: ",").map(String.init)) }
            for snapshotCase in Case.allCases {
                if let filter, !filter.contains(snapshotCase.rawValue) { continue }
                // References keep their `entityScreen.<case>.png` prefix.
                await SnapshotHost.assert(
                    snapshotCase, store: context.store, defaults: context.defaults.defaults,
                    testName: "entityScreen")
            }
        }
    }
#endif
