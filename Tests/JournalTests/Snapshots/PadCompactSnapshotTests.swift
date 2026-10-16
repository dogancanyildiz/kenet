#if os(iOS)
    import SwiftUI
    import Testing

    @testable import Journal

    /// The app beside another in Split View on the 13-inch (440×1032 pt, compact × regular):
    /// the real `AdaptiveNavigation` picks the tab shell. Light and AX3.
    enum PadCompactCase: String, CaseIterable, Sendable {
        case todayLight, todayAX3

        var dynamicType: SnapshotDynamicType { self == .todayAX3 ? .accessibility3 : .medium }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadCompactSnapshotTests {
        @Test(arguments: PadCompactCase.allCases)
        func compact(_ snapshotCase: PadCompactCase) async throws {
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "compact", canvas: .padCompact,
                dynamicType: snapshotCase.dynamicType,
                masks: [PadSnapshotHost.Mask.tabBar(on: .padCompact)]
            ) { scene in
                AnyView(AdaptiveNavigation(store: scene.store))
            }
        }
    }
#endif
