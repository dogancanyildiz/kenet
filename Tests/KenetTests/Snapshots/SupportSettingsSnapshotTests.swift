#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    @testable import Kenet

    enum SupportSettingsSnapshotCase: String, CaseIterable, Sendable {
        case loadedLight
        case unavailableLight
        case thankedLight
        case unverifiedLight

        var colorScheme: SnapshotColorScheme { .light }

        var dynamicType: SnapshotDynamicType { .medium }
    }

    /// The support page over a store in memory (``InMemorySupportStorefront``): no App Store.
    @MainActor @Suite("Support settings snapshots", .serialized)
    struct SupportSettingsSnapshotTests {
        static func service(for snapshotCase: SupportSettingsSnapshotCase) async -> SupportService {
            let storefront = InMemorySupportStorefront()
            switch snapshotCase {
            case .loadedLight, .thankedLight: break
            case .unavailableLight: storefront.catalog = nil
            case .unverifiedLight: storefront.purchaseOutcome = .unverified
            }
            let service = SupportService(storefront: storefront)
            await service.loadProducts()
            switch snapshotCase {
            case .thankedLight, .unverifiedLight: await service.buy(.medium)
            case .loadedLight, .unavailableLight: break
            }
            return service
        }

        @Test(arguments: SupportSettingsSnapshotCase.allCases)
        func support(_ snapshotCase: SupportSettingsSnapshotCase) async throws {
            let context = try TaskTestContext(sample: false)
            defer { context.clean() }
            let service = await Self.service(for: snapshotCase)

            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                testName: "support"
            ) {
                NavigationStack {
                    SupportSettingsView(service: service)
                }
                .environment(\.locale, snapshotLocale)
            }
        }
    }
#endif
