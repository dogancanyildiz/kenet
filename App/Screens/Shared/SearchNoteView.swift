import SwiftUI

/// Reads the original body for display; wikilink markup and block ids are hidden in the UI only.
struct SearchNoteView: View {
    let store: IndexStore
    let file: String
    @State private var bodyText = ""
    @State private var errorText: String?
    @State private var isLoaded = false
    @Environment(\.inkSheetDismissAction) private var sheetDismiss
    @Environment(\.dismiss) private var dismiss

    private var noteTitle: String { SearchPreviewText.noteDisplayName(file) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                InkPageTitle(verbatim: noteTitle) { SearchButton() }
                Group {
                    if let errorText {
                        Text(verbatim: errorText).foregroundStyle(.ink.danger)
                    } else if isLoaded {
                        Text(verbatim: bodyText).textSelection(.enabled)
                            .font(.ink.content)
                            .inkJournalParagraph()
                            .foregroundStyle(.ink.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView("Yükleniyor…")
                    }
                }
                .padding(.horizontal, InkSpacing.margin)
            }
        }
        .inkPage()
        .inkPageScrollColumn()
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
            do {
                let document = try await store.document(at: file)
                try Task.checkCancellation()
                let raw = document.lines.dropFirst(document.frontmatterLineRange?.upperBound ?? 0)
                    .map(\.displayText).joined(separator: "\n")
                bodyText = VaultDisplayText.multiline(raw)
                isLoaded = true
            } catch is CancellationError {
            } catch {
                errorText = DayEditError.message(for: error)
            }
        }
    }
}
