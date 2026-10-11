#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Journal

    /// Affedilen ısı haritası hücresi: içi boş vurgu çerçevesi, boş hücrenin çukurundan ayrı.
    enum ForgivenHeatmapSnapshotCase: String, CaseIterable, Sendable {
        case light, dark, contrast

        var colorScheme: SnapshotColorScheme {
            self == .dark ? .dark : .light
        }

        var increaseContrast: Bool { self == .contrast }
    }

    @MainActor @Suite("Forgiven heatmap cell snapshots")
    struct ForgivenHeatmapSnapshotTests {
        @Test(arguments: ForgivenHeatmapSnapshotCase.allCases)
        func cell(_ snapshotCase: ForgivenHeatmapSnapshotCase) async throws {
            let context = try SnapshotHost.makeContext()
            defer { context.clean() }
            await context.start()
            await SnapshotHost.assertView(
                colorScheme: snapshotCase.colorScheme,
                dynamicType: .medium,
                increaseContrast: snapshotCase.increaseContrast,
                named: snapshotCase.rawValue,
                store: context.store,
                size: CGSize(width: 390, height: 160),
                testName: "forgivenHeatmap"
            ) {
                Self.row
                    .environment(\.locale, snapshotLocale)
            }
        }

        private static var row: some View {
            HStack(alignment: .top, spacing: 16) {
                ForEach([HeatmapCellKind.empty, .partial, .full, .forgiven], id: \.self) { kind in
                    VStack(spacing: 6) {
                        HeatmapCell(
                            kind: kind, size: 22,
                            accessibilityValue: Text(verbatim: kind.rawValue),
                            accessibilityLabel: Text(verbatim: kind.rawValue))
                        Text(verbatim: kind.rawValue)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
            .padding(InkSpacing.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .inkPage()
        }
    }
#endif
