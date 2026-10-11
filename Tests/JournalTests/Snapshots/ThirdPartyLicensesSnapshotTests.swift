#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Journal

    enum ThirdPartyLicensesSnapshotCase: String, CaseIterable, Sendable {
        case light, dark, ax3

        var colorScheme: SnapshotColorScheme {
            switch self {
            case .dark: .dark
            case .light, .ax3: .light
            }
        }

        var dynamicType: SnapshotDynamicType {
            switch self {
            case .ax3: .accessibility3
            case .light, .dark: .medium
            }
        }
    }

    @MainActor @Suite("Third-party licenses snapshots", .serialized)
    struct ThirdPartyLicensesSnapshotTests {
        @Test(arguments: ThirdPartyLicensesSnapshotCase.allCases)
        func licenses(_ snapshotCase: ThirdPartyLicensesSnapshotCase) async throws {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }

            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                testName: "licenses"
            ) {
                NavigationStack {
                    ThirdPartyLicensesView()
                }
                .environment(\.locale, snapshotLocale)
            }
        }
    }
#endif
