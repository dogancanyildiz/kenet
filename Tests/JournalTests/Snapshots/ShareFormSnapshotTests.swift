#if os(iOS)
    import SwiftUI
    import Testing

    @testable import Journal

    /// The share extension's form (`ShareFormView`), drawn in the app host: a Safari page shared
    /// (title and link), light, dark and AX3; and selected text whose write failed (no App Group).
    enum ShareFormSnapshotCase: String, CaseIterable, Sendable {
        case linkLight, linkDark, linkAX3, failedLight

        var colorScheme: SnapshotColorScheme { self == .linkDark ? .dark : .light }
        var dynamicType: SnapshotDynamicType { self == .linkAX3 ? .accessibility3 : .medium }

        var text: String {
            switch self {
            case .failedLight: EntryWriting.prefill(title: nil, url: nil, text: "Çınaraltı Kafe'de\nkahve")
            default:
                EntryWriting.prefill(
                    title: "Kısa günlük tutmanın yararları", url: URL(string: "https://example.com/gunluk"), text: nil)
            }
        }
    }

    @MainActor @Suite("Share form snapshots")
    struct ShareFormSnapshotTests {
        @Test(arguments: ShareFormSnapshotCase.allCases)
        func form(_ snapshotCase: ShareFormSnapshotCase) async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: snapshotCase.dynamicType,
                increaseContrast: false,
                named: snapshotCase.rawValue,
                store: context.store,
                testName: "shareForm"
            ) {
                ShareFormView(
                    text: .constant(snapshotCase.text), isSaving: false, failed: snapshotCase == .failedLight,
                    onCancel: {},
                    onConfirm: {}, focusesOnAppear: false
                )
                .environment(\.locale, snapshotLocale)
            }
        }
    }
#endif
