import SwiftUI
import Testing

@testable import Journal

enum VaultCloudSnapshotCase: String, CaseIterable, Sendable {
    case onboardingCloud, onboardingLocal, settingsCloud, settingsLocal, cloudUnavailable, cloudFolderMissing, migration
}

@MainActor
private enum VaultCloudSnapshotHost {
    static func prepare(_ name: VaultCloudSnapshotCase) async throws -> CloudVaultContext {
        let context = try CloudVaultContext(available: name != .onboardingLocal && name != .cloudUnavailable)
        try await context.store.refreshCloudAvailability()
        switch name {
        case .settingsCloud: await context.store.createCloudVault()
        case .settingsLocal: await context.store.continueLocally()
        case .cloudUnavailable, .cloudFolderMissing:
            context.defaults.defaults.set("icloud", forKey: VaultLocation.kindKey)
            await context.store.start()
        default: break
        }
        return context
    }

    @ViewBuilder
    static func view(_ name: VaultCloudSnapshotCase, store: IndexStore) -> some View {
        Group {
            switch name {
            case .onboardingCloud, .onboardingLocal: OnboardingView(store: store)
            case .settingsCloud, .settingsLocal: VaultSettingsView(store: store)
            case .cloudUnavailable, .cloudFolderMissing: VaultInaccessibleView(store: store)
            case .migration: VaultCloudMigrationView(store: store)
            }
        }
        .environment(\.vaultPathDisplayOverride, VaultPathDisplay.snapshotExample)
        .environment(\.locale, Locale(identifier: "tr_TR"))
        .environment(\.colorScheme, .light)
    }
}

#if os(iOS)
    @MainActor
    @Suite("iCloud vault snapshots", .serialized)
    struct VaultCloudSnapshotTests {
        @Test(arguments: VaultCloudSnapshotCase.allCases)
        func phone(_ name: VaultCloudSnapshotCase) async throws {
            let context = try await VaultCloudSnapshotHost.prepare(name)
            defer { context.clean() }
            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: .medium, increaseContrast: false,
                named: name.rawValue, store: context.store, testName: "vaultCloud"
            ) {
                VaultCloudSnapshotHost.view(name, store: context.store)
            }
        }
    }
#endif

#if os(macOS)
    import AppKit
    import SnapshotTesting

    @MainActor
    @Suite(
        "iCloud vault snapshots (macOS)", .serialized,
        .enabled(if: MacSnapshotEnvironment.isEnabled, "Mac references are recorded by CI."))
    struct VaultCloudMacSnapshotTests {
        @Test(arguments: VaultCloudSnapshotCase.allCases)
        func mac(_ name: VaultCloudSnapshotCase) async throws {
            let context = try await VaultCloudSnapshotHost.prepare(name)
            defer { context.clean() }
            let size = CGSize(width: 600, height: 800)
            let root = VaultCloudSnapshotHost.view(name, store: context.store)
                .transaction { $0.animation = nil }
                .frame(width: size.width, height: size.height)
            MacSnapshotEnvironment.requireOverlayScrollers()
            let host = NSHostingView(rootView: root)
            host.frame = NSRect(origin: .zero, size: size)
            let window = MacSnapshotWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            // A fixed frame pump allows SwiftUI/AppKit to draw; no data load depends on timing here.
            try await Task.sleep(for: .milliseconds(300))
            let scale = MacSnapshotWindow.scale
            let rep = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                    pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            let record = ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]
                .flatMap(SnapshotTestingConfiguration.Record.init(rawValue:))
            assertSnapshot(
                of: image, as: .image(precision: 0.9999, perceptualPrecision: 0.995),
                named: name.rawValue, record: record, file: #filePath, testName: "vaultCloud")
        }
    }
#endif
