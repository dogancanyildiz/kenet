import SwiftUI

/// Reads the original body, including unknown syntax, without offering edits.
struct SearchNoteView: View {
    let store: IndexStore
    let file: String
    @State private var bodyText = ""
    @State private var errorText: String?
    @State private var isLoaded = false

    var body: some View {
        ScrollView {
            if let errorText {
                Text(verbatim: errorText).foregroundStyle(.red)
            } else if isLoaded {
                Text(verbatim: bodyText).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView("Yükleniyor…")
            }
        }
        .padding()
        .navigationTitle((file as NSString).lastPathComponent)
        .toolbar { SearchButton() }
        .task(id: store.lastUpdated) {
            isLoaded = false
            errorText = nil
            bodyText = ""
            do {
                let document = try await store.document(at: file)
                try Task.checkCancellation()
                bodyText = document.lines.dropFirst(document.frontmatterLineRange?.upperBound ?? 0)
                    .map(\.displayText).joined(separator: "\n")
                isLoaded = true
            } catch is CancellationError {
            } catch {
                errorText = DayEditError.message(for: error)
            }
        }
    }
}
