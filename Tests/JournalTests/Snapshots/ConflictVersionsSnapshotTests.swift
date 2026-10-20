#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultIndex

    @testable import Journal

    /// Diagnostics' two conflict sections: files with unresolved iCloud versions (from a fake
    /// version source) and the versions merges saved under `conflicts/`.
    enum ConflictVersionsSnapshotCase: String, CaseIterable, Sendable {
        case conflictsLight
    }

    @MainActor @Suite("Conflict versions snapshots", .serialized, .timeLimit(.minutes(2)))
    struct ConflictVersionsSnapshotTests {
        /// 2026-10-02 11:05:33 and 14:20:00 UTC; the second one newest.
        private static let source = FakeConflictVersionSource([
            "journal/2026-10-02.md": [
                ConflictVersion(modificationTime: 1_790_939_133, deviceName: "Ada'nın Mac'i"),
                ConflictVersion(modificationTime: 1_790_950_800, deviceName: "Ece'nin iPhone'u"),
            ],
            "2026-10-02 (conflict 20261002T110533Z).md": [
                ConflictVersion(modificationTime: 0, deviceName: nil)
            ],
        ])

        @Test(arguments: ConflictVersionsSnapshotCase.allCases)
        func conflictVersions(_ snapshotCase: ConflictVersionsSnapshotCase) async throws {
            let context = try ConflictVaultTestContext(
                folder: "Library/Mobile Documents/com~apple~CloudDocs", source: Self.source)
            defer { context.clean() }
            await context.start()
            let files = try await context.store.computeConflictedFiles()
            let copies = try await context.store.computeConflictCopies()
            #expect(files.count == 2)
            #expect(copies == (try ConflictVaultTestContext.expectedConflictCopies()))
            await SnapshotHost.assertView(
                colorScheme: .light,
                dynamicType: .medium,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                size: snapshotCanvasSize,
                testName: "conflictVersions"
            ) {
                NavigationStack {
                    // The sections alone: the full Diagnostics page shows the time of the last update.
                    List {
                        ConflictedFilesSection(files: files)
                        ConflictCopiesSection(copies: copies)
                    }
                    .listStyle(.plain)
                    .inkPageScrollColumn()
                    .inkPage()
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.openSearch, {})
            }
        }
    }
#endif
