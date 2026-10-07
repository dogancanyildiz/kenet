#if DEBUG
    import SwiftUI

    /// Debug gallery for control and surface components (fictional sample copy only).
    struct ComponentGalleryControls: View {
        @State private var mode: QuickEntryMode = .event
        @State private var canSubmit = true

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("QuickEntryCapsule") {
                        QuickEntryCapsule(mode: $mode, canSubmit: canSubmit, onSubmit: {}) {
                            Text(verbatim: "Gününden bir an…")
                                .font(.ink.placeholder)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Toggle(isOn: $canSubmit) {
                            Text(verbatim: "canSubmit")
                        }
                        .tint(Color.ink.accent)
                    }

                    // Manşet row, tabs, labeled menu, filter field, accent switch.
                    ComponentGalleryPatterns()

                    section("Sheet: .inkSheet / InkSheetScaffold") {
                        ForEach(ComponentGallerySheet.Kind.allCases, id: \.self) { kind in
                            NavigationStack { ComponentGallerySheet(kind: kind) }
                                .frame(height: 260)
                        }
                    }

                    section("TagChip") {
                        HStack {
                            TagChip(title: "project/alpha", systemImage: "number")
                            TagChip(title: "selected", isSelected: true, filled: true)
                            TagChip(title: "closable", onDismiss: {})
                        }
                    }

                    section("EmptyState") {
                        EmptyState(verbatim: "Henüz olay yok.", actionTitle: "Yeniden dene", action: {})
                    }

                    section("InkProgress") {
                        InkProgress(kind: .indeterminate(label: "İndeks güncelleniyor…"))
                        InkProgress(kind: .determinate(completed: 3, total: 10, label: nil))
                    }

                    section("HeatmapCell") {
                        HStack(spacing: 6) {
                            ForEach(HeatmapCellKind.allCases, id: \.self) { kind in
                                VStack(spacing: 4) {
                                    HeatmapCell(
                                        kind: kind,
                                        size: 18,
                                        accessibilityValue: Text(verbatim: kind.rawValue),
                                        accessibilityLabel: Text(verbatim: kind.rawValue))
                                    Text(verbatim: kind.rawValue)
                                        .font(.ink.meta)
                                        .foregroundStyle(Color.ink.secondaryText)
                                }
                            }
                        }
                    }

                    section("InfoBand") {
                        InfoBand(kind: .info, verbatim: "Index rebuilt from files.")
                        InfoBand(
                            kind: .warning, verbatim: "Vault bookmark expired.",
                            actionTitle: "Yeniden dene", action: {}, onDismiss: {})
                        InfoBand(kind: .error, verbatim: "Could not write the day file.", onDismiss: {})
                    }

                    section("InkSurface / InkKanbanCard") {
                        Text(verbatim: "Sheet body")
                            .padding()
                            .inkSurface()
                        InkKanbanCard(isDragging: false) {
                            Text(verbatim: "Kanban paper card")
                                .font(.ink.content)
                        }
                        InkKanbanCard(isDragging: true) {
                            Text(verbatim: "Dragging")
                                .font(.ink.content)
                        }
                    }

                    section("Button styles") {
                        HStack {
                            Button("Gönder") {}.buttonStyle(InkPrimaryButtonStyle())
                            Button("Yeniden dene") {}.buttonStyle(InkTextButtonStyle())
                            Button("Sil") {}.buttonStyle(InkDestructiveButtonStyle())
                        }
                        HStack {
                            Button("Gönder") {}.buttonStyle(InkPrimaryButtonStyle()).disabled(true)
                            Button("Yeniden dene") {}.buttonStyle(InkTextButtonStyle()).disabled(true)
                            Button("Sil") {}.buttonStyle(InkDestructiveButtonStyle()).disabled(true)
                        }
                    }

                    section("LargeNumberText") {
                        LargeNumberText(verbatim: "48")
                    }
                }
                .padding(InkSpacing.margin)
            }
            .inkPage()
        }

        private func section<Content: View>(
            _ title: String, @ViewBuilder content: () -> Content
        ) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: title)
                    .font(.ink.section)
                    .foregroundStyle(Color.ink.secondaryText)
                content()
            }
        }
    }
#endif
