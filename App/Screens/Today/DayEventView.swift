import SwiftUI
import VaultFormat

struct DayEventView: View {
    let store: IndexStore
    let day: CalendarDate
    let event: EventRow
    @Environment(\.locale) private var locale
    @State private var editor: EventEditorModel?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let time = event.time {
                Text(
                    LocalDay.instant(for: day, time: time, timeZone: .gmt),
                    format: Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: .gmt)
                )
                .font(.subheadline).foregroundStyle(.secondary)
            }
            LinkedTextView(text: event.text, store: store)
            if let error = errorText { Text(verbatim: error).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Metni düzenle", systemImage: "pencil") {
                editor = EventEditorModel(store: store, day: day, row: event)
            }
            Button("Sil", systemImage: "trash", role: .destructive) {
                let model = EventEditorModel(store: store, day: day, row: event)
                Task {
                    await model.load()
                    if model.target != nil { await model.delete() }
                    errorText = model.errorText
                }
            }
        }
        .sheet(item: $editor) { model in
            NavigationStack { EventTextEditor(model: model) }
                .presentationDetents([.medium, .large])
                .frame(minWidth: 320, minHeight: 200)
        }
    }
}
