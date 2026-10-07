#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultFormat

    @testable import Journal

    /// Günlük listesi, varlık okuma sayfası ve arama: açık / koyu / AX3 / Kontrastı Artır.
    @MainActor @Suite("Journal entity snapshots", .serialized)
    struct JournalEntitySnapshotTests {
        enum Case: String, CaseIterable, Sendable, SnapshotCaseConfiguring {
            case daysLight, daysDark, daysAX3, daysContrast, daysSelected
            case entityLight, entityDark, entityAX3, entityContrast
            case searchLight, searchDark, searchAX3, searchContrast

            var screen: SnapshotScreen {
                switch self {
                case .daysLight, .daysDark, .daysAX3, .daysContrast: .days
                case .daysSelected: .daysSelected
                case .entityLight, .entityDark, .entityAX3, .entityContrast: .entity
                case .searchLight, .searchDark, .searchAX3, .searchContrast: .search
                }
            }

            var colorScheme: SnapshotColorScheme {
                switch self {
                case .daysDark, .entityDark, .searchDark: .dark
                default: .light
                }
            }

            var dynamicType: SnapshotDynamicType {
                switch self {
                case .daysAX3, .entityAX3, .searchAX3: .accessibility3
                default: .medium
                }
            }

            var increaseContrast: Bool {
                switch self {
                case .daysContrast, .entityContrast, .searchContrast: true
                default: false
                }
            }
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
