#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    /// The iPad split shell at accessibility text sizes, where the sidebar and the list column are
    /// narrow for the text: every sidebar name, the Günlük column's links and month, and the
    /// Kişiler column's actions wrap and are read whole, never cut with "…" (the accessibility
    /// audit's textClipped check). AX5 is the size the audit found them cut at; AX3 also draws the
    /// entity page's byline beside the column.
    enum PadLargeTextCase: String, CaseIterable, Sendable {
        case todayLandscapeAX5
        case peopleLandscapeAX3

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .todayLandscapeAX5: .accessibility5
            case .peopleLandscapeAX3: .accessibility3
            }
        }

        var masks: [CGRect] {
            [PadSnapshotHost.Mask.sidebarButton]
                + PadSnapshotHost.Mask.sidebarOutline(on: .pad13Landscape, dynamicType: dynamicType)
        }
    }

    @MainActor
    @Suite(.serialized, .enabled("iPad simulator only", PadSnapshotHost.isPadSimulator))
    struct PadLargeTextSnapshotTests {
        @Test(arguments: PadLargeTextCase.allCases)
        func largeText(_ snapshotCase: PadLargeTextCase) async throws {
            try await PadSnapshotHost.assertWindow(
                named: snapshotCase.rawValue, testName: "largeText", canvas: .pad13Landscape,
                dynamicType: snapshotCase.dynamicType, masks: snapshotCase.masks
            ) { scene in
                let navigation = ShellNavigationState()
                if snapshotCase == .peopleLandscapeAX3 {
                    let store = scene.store
                    let entity = try #require(
                        store.content.entities.first { $0.name == "Deniz Arıkan" } ?? store.content.entities.first)
                    navigation.section = .people
                    navigation.selectedEntityKind = "person"
                    navigation.selectedEntity = entity.id
                    navigation.selectedSummary = entity
                }
                return AnyView(AdaptiveNavigation(store: scene.store, navigation: navigation))
            }
        }
    }
#endif
