#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit
    import VaultIndex

    @testable import Journal

    /// The synced-folder band (Settings → Kasa, vault preparation) and the copy files of Diagnostics.
    enum SyncedFolderSnapshotCase: String, CaseIterable, Sendable {
        case vaultLight, vaultImportLight, copyFilesLight

        var dynamicType: SnapshotDynamicType { .medium }

        var canvas: CGSize { snapshotCanvasSize }

        /// Fictional paths on screen: no host user name or temporary directory.
        var displayedPath: String {
            self == .vaultImportLight
                ? "/Users/ada/Library/CloudStorage/Dropbox/Notlar"
                : "/Users/ada/Library/Mobile Documents/com~apple~CloudDocs/Kenet"
        }
    }

    @MainActor @Suite("Synced folder snapshots", .serialized, .timeLimit(.minutes(2)))
    struct SyncedFolderSnapshotTests {
        @Test(arguments: SyncedFolderSnapshotCase.allCases)
        func syncedFolder(_ snapshotCase: SyncedFolderSnapshotCase) async throws {
            let context = try SyncedVaultTestContext()
            defer { context.clean() }
            await context.start()
            #expect(context.store.syncedFolder == .iCloudDrive)
            var importModel: VaultImportModel?
            var copies: [CopyFile] = []
            switch snapshotCase {
            case .vaultImportLight:
                // A plain Markdown folder in Dropbox: it needs preparation, so the report opens.
                let folder = context.directory.appendingPathComponent("Library/CloudStorage/Dropbox/Notlar")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data("- Pazar planı\n".utf8).write(to: folder.appendingPathComponent("Plan.md"))
                importModel = try await VaultImportModel(root: folder)
            case .copyFilesLight:
                copies = try await context.store.computeCopyFiles()
                #expect(copies == (try SyncedVaultTestContext.expectedCopies()))
            case .vaultLight:
                break
            }
            await SnapshotHost.assertView(
                colorScheme: .light,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                size: snapshotCase.canvas,
                testName: "syncedFolder"
            ) {
                NavigationStack {
                    switch snapshotCase {
                    case .vaultLight:
                        VaultSettingsView(store: context.store).navigationTitle("Kasa")
                    case .vaultImportLight:
                        if let importModel {
                            VaultImportView(store: context.store, model: importModel)
                        }
                    case .copyFilesLight:
                        // The section alone: the full Diagnostics page shows the time of the last update.
                        List {
                            CopyFilesSection(copies: copies)
                        }
                        .listStyle(.plain)
                        .inkPageScrollColumn()
                        .inkPage()
                    }
                }
                .environment(\.locale, snapshotLocale)
                .environment(\.openSearch, {})
                .environment(\.vaultPathDisplayOverride, snapshotCase.displayedPath)
            }
        }
    }
#endif
