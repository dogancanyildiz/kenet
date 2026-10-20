#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing
    import VaultIndex

    @testable import Journal

    /// The mounted Diagnostics page loads both conflict lists from the store on its own: the rows
    /// of an iCloud vault's conflicting versions and its saved conflict copies reach the screen.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct DiagnosticsConflictWiringTests {
        private let watchdog = HostedTestWatchdog()

        @Test func pageShowsConflictedFilesAndConflictCopies() async throws {
            let source = FakeConflictVersionSource([
                "journal/2026-10-02.md": [
                    ConflictVersion(modificationTime: 1_790_939_133, deviceName: "Ada'nın Mac'i"),
                    ConflictVersion(modificationTime: 1_790_950_800, deviceName: "Ece'nin iPhone'u"),
                ]
            ])
            let context = try ConflictVaultTestContext(
                folder: "Library/Mobile Documents/com~apple~CloudDocs", source: source)
            defer { context.clean() }
            await context.start()
            #expect(context.store.syncedFolder == .iCloudDrive)
            let copies = try ConflictVaultTestContext.expectedConflictCopies().map(\.copy)

            let mount = HostedLayout.Mount(
                DiagnosticsView(store: context.store), size: CGSize(width: 720, height: 4000))
            defer { mount.close() }
            func texts() -> [String] { HostedAccessibilityTree.texts(under: mount) }
            func shows(_ text: String) -> Bool { texts().contains { $0.contains(text) } }
            let devices = "Ece'nin iPhone'u, Ada'nın Mac'i"
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { shows(devices) && copies.allSatisfy(shows) })
            else { return }

            #expect(shows(String(localized: "Çakışan sürümler")))
            #expect(shows(String(localized: "Çakışma kopyaları")))
            #expect(shows(devices), "the conflicted file's row: \(texts())")
            for copy in copies { #expect(shows(copy), "\(copy)") }
        }
    }
#endif
