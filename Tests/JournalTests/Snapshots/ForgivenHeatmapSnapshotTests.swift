#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Journal

    /// Affedilen ısı haritası hücresi: kesik çizgili vurgu çerçevesi; bugünün kesiksiz çerçevesinden biçimle ayrı.
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

        /// Density kinds, both forgiven kinds, and an empty today: the dashed frame against the solid ring.
        private static let cells: [(kind: HeatmapCellKind, isToday: Bool, label: String)] = [
            (.empty, false, "empty"), (.partial, false, "partial"), (.full, false, "full"),
            (.forgiven, false, "forgiven"), (.forgivenPartial, false, "f+part"), (.empty, true, "today"),
        ]

        private static var row: some View {
            HStack(alignment: .top, spacing: 12) {
                ForEach(cells, id: \.label) { cell in
                    VStack(spacing: 6) {
                        HeatmapCell(
                            kind: cell.kind, size: 22, isToday: cell.isToday,
                            accessibilityValue: Text(verbatim: cell.label),
                            accessibilityLabel: Text(verbatim: cell.label))
                        // Legend size, where the dashes are smallest.
                        HeatmapCell(
                            kind: cell.kind, size: 10, isToday: cell.isToday,
                            accessibilityValue: Text(verbatim: cell.label),
                            accessibilityLabel: Text(verbatim: cell.label))
                        Text(verbatim: cell.label)
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
