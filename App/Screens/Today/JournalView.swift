import SwiftUI
import VaultFormat

/// Journal paragraphs remain readable without exposing an editor.
struct JournalView: View {
    let store: IndexStore
    let date: CalendarDate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(store.content.day(on: date).journal) { row in
                    LinkedTextView(text: row.text, store: store)
                        .font(row.headingLevel == nil ? .body : .headline)
                        .textSelection(.enabled)
                }
            }
            .padding().frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity)
        }
        .navigationTitle("Günlük yazısı")
        .toolbar { SearchButton() }
    }
}
