import SwiftUI
import VaultFormat

struct DayEventView: View {
    let store: IndexStore
    let day: CalendarDate
    let event: EventRow
    @Environment(\.locale) private var locale
    @State private var editor: EventEditorModel?
    @State private var errorText: String?
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()
    @State private var linkDestination: LinkDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            InkEventRow(
                time: event.time.map { DayEventView.formattedEventTime($0, locale: locale) },
                segments: InkLinkMapping.segments(from: event.text, entities: store.content.entities),
                openURL: { openLink($0) }
            )
            if let error = errorText {
                InfoBand(kind: .error, verbatim: error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("event.row")
        .accessibilityLabel(Text(verbatim: event.text.plainText))
        .contextMenu {
            Button("Metni düzenle", systemImage: "pencil") {
                editor = EventEditorModel(store: store, day: day, row: event)
            }
            Button("Sil", systemImage: "trash", role: .destructive) {
                deleteConfirmation.request(.pending)
            }
        }
        .destructiveConfirmationDialog("Olayı sil?", confirmation: $deleteConfirmation) { _ in
            let model = EventEditorModel(store: store, day: day, row: event)
            Task {
                await model.load()
                if model.target != nil { await model.delete() }
                errorText = model.errorText
            }
        }
        .sheet(item: $editor) { model in
            NavigationStack { EventTextEditor(model: model) }
                .presentationDetents([.medium, .large])
                .frame(minWidth: 320, minHeight: 200)
        }
        .sheet(item: $linkDestination) { link in
            NavigationStack {
                Group {
                    if let entity = link.entity {
                        EntityView(store: store, entity: entity)
                    } else if link.path == nil {
                        UnresolvedEntityView(store: store, target: link.name)
                    } else {
                        ContentUnavailableView(
                            "Bu bağlantı kişi veya konum değil", systemImage: "doc.text",
                            description: Text(verbatim: link.name))
                    }
                }
                .toolbar { Button("Kapat") { linkDestination = nil } }
            }
            .frame(minWidth: 300, minHeight: 300)
        }
    }

    nonisolated static func formattedEventTime(_ time: EventTime, locale: Locale) -> String {
        EventTimeFormat.string(for: time, locale: locale)
    }

    private func openLink(_ url: URL) {
        guard url.scheme == "journal-entity",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let name = components.queryItems?.first(where: { $0.name == "name" })?.value
        else { return }
        let path = components.queryItems?.first(where: { $0.name == "path" })?.value
        linkDestination = LinkDestination(
            name: name, path: path, entity: store.content.entities.first { $0.id == path })
    }

    private struct LinkDestination: Identifiable {
        let name: String
        let path: String?
        let entity: EntitySummary?
        var id: String { path ?? name }
    }
}
