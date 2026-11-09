import SwiftUI
import VaultFormat

/// Reads the original body for display; wikilink markup and block ids are hidden in the UI only.
struct SearchNoteView: View {
    let store: IndexStore
    let file: String
    @State private var bodyText = ""
    @State private var errorText: String?
    @State private var isLoaded = false
    /// Days whose events and paragraphs link to this note, newest first (the entity timeline query).
    @State private var backlinks: [EntityTimelineDay] = []
    @Environment(\.inkSheetDismissAction) private var sheetDismiss
    @Environment(\.dismiss) private var dismiss

    private var noteTitle: String { SearchPreviewText.noteDisplayName(file) }

    private var masthead: InkPageTitle<some View> {
        InkPageTitle(verbatim: noteTitle) { SearchButton() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                InkScrolledMasthead(masthead)
                Group {
                    if let errorText {
                        Text(verbatim: errorText).foregroundStyle(.ink.danger)
                    } else if isLoaded {
                        VStack(alignment: .leading, spacing: InkSpacing.section) {
                            // Reading text stays on the page, full width; only the backlinks are a card.
                            Text(verbatim: bodyText).textSelection(.enabled)
                                .font(.ink.content)
                                .inkJournalParagraph()
                                .foregroundStyle(.ink.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !backlinks.isEmpty { backlinksSection }
                        }
                    } else {
                        ProgressView("Yükleniyor…")
                    }
                }
                .padding(.horizontal, InkSpacing.margin)
            }
            .inkPageColumn()
        }
        .inkPinnedMasthead(masthead, spacing: 12)
        .inkPage()
        // Mac: keep the sheet action bar ("Kapat") on nested search destinations. iPhone keeps
        // the pushed page chrome only (back to results); adding a second "Kapat" would change it.
        #if os(macOS)
            .inkSheet(
                verbatim: noteTitle, closeIdentifier: "button.search.note.close",
                onClose: { if let sheetDismiss { sheetDismiss() } else { dismiss() } }
            )
            // System Back paints the note name beside the chevron; replace it with a title-free
            // chevron that only pops to search results ("Kapat" still dismisses the sheet).
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Geri", systemImage: "chevron.backward") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkAccessibilityIdentifier("button.search.note.back")
                }
            }
        #else
            .inkPageNavigationTitle(verbatim: noteTitle)
        #endif
        .task(id: store.lastUpdated) {
            isLoaded = false
            errorText = nil
            bodyText = ""
            backlinks = []
            do {
                let document = try await store.document(at: file)
                try Task.checkCancellation()
                let raw = document.lines.dropFirst(document.frontmatterLineRange?.upperBound ?? 0)
                    .map(\.displayText).joined(separator: "\n")
                bodyText = VaultDisplayText.multiline(raw)
                backlinks = (try? await store.computeEntityTimeline(for: file)) ?? []
                isLoaded = true
            } catch is CancellationError {
            } catch {
                errorText = DayEditError.message(for: error)
            }
        }
    }

    private var backlinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Bu nota bağlananlar", count: backlinks.reduce(0) { $0 + $1.rows.count })
            InkCard {
                ForEach(Array(backlinks.enumerated()), id: \.element.id) { offset, day in
                    if offset > 0 { InkCardDivider() }
                    ForEach(day.rows) { row in
                        NavigationLink { DayView(store: store, date: day.date) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(LocalDay.instant(for: day.date), format: .dateTime.day().month(.abbreviated))
                                    .font(.ink.value)
                                    .foregroundStyle(.ink.secondaryText)
                                LinkedTextView(text: row.text, store: store)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: TapTarget.minimumLength)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
