#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    @MainActor @Suite("Quick entry widget snapshots", .serialized)
    struct QuickEntryWidgetSnapshotTests {
        @Test func smallLight() async throws {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }
            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: .medium, increaseContrast: false,
                named: "smallLight", store: context.store,
                size: CGSize(width: 210, height: 210), testName: "quickEntry"
            ) {
                QuickEntryWidgetView(date: snapshotNow)
                    .padding(16)
                    .frame(width: 170, height: 170)
                    .background(WidgetTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ink.well)
                    .environment(\.locale, snapshotLocale)
                    .environment(\.timeZone, snapshotTimeZone)
            }
        }
    }
#endif
