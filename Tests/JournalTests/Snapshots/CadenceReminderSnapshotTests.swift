#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Journal

    enum CadenceReminderSnapshotCase: String, CaseIterable, Sendable {
        case light

        var colorScheme: SnapshotColorScheme { .light }

        var dynamicType: SnapshotDynamicType { .medium }

        var canvas: CGSize { CGSize(width: 390, height: 1700) }
    }

    @MainActor @Suite("Cadence reminder snapshots")
    struct CadenceReminderSnapshotTests {
        @Test(arguments: CadenceReminderSnapshotCase.allCases)
        func cadenceReminder(_ snapshotCase: CadenceReminderSnapshotCase) async throws {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }
            let service = NotificationService(
                center: FakeNotificationCenter(), defaults: context.defaults.defaults,
                now: { snapshotNow }, timeZone: { snapshotTimeZone })
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                size: snapshotCase.canvas,
                clock: snapshotNow,
                testName: "cadenceReminder"
            ) {
                NavigationStack {
                    NotificationSettingsView()
                }
                .environment(service)
                .environment(\.locale, snapshotLocale)
                .environment(\.timeZone, snapshotTimeZone)
                .environment(\.clockNow, { snapshotNow })
            }
        }
    }
#endif
