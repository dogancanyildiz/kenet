#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    @MainActor @Suite("Lock screen widget snapshots")
    struct LockScreenWidgetSnapshotTests {
        @Test(arguments: [LockScreenLayout.rectangular, .circular])
        func accessory(_ layout: LockScreenLayout) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let date = WidgetSnapshotTests.noon
            let day = WidgetSnapshot.Day(
                date: "2026-09-20", goals: [],
                events: [
                    .init(title: "Çizim atölyesi", start: date, end: date.addingTimeInterval(3600), isAllDay: false)
                ], openTaskCount: 3)
            let rectangular = layout == .rectangular
            let size = rectangular ? CGSize(width: 172, height: 76) : CGSize(width: 76, height: 76)
            await SnapshotHost.assertView(
                colorScheme: .light, dynamicType: .medium, increaseContrast: false,
                named: rectangular ? "rectangularLight" : "circularLight", store: context.store,
                size: CGSize(width: size.width + 40, height: size.height + 40), testName: "accessory"
            ) {
                LockScreenWidgetView(day: day, date: date, hideContent: false, layout: layout)
                    .padding(4)
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.locale, snapshotLocale)
            }
        }
    }
#endif
