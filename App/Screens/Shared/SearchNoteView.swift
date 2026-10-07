import SwiftUI

/// Reads the original body for display; wikilink markup and block ids are hidden in the UI only.
struct SearchNoteView: View {
    let store: IndexStore
    let file: String
    @State private var bodyText = ""
    @State private var errorText: String?
    @State private var isLoaded = false

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
        .inkPageColumn()
        .inkPageNavigationTitle(verbatim: noteTitle)
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
