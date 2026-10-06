import SwiftUI
import VaultFormat

struct DayTaskView: View {
    let store: IndexStore
    let row: TaskRow
    let isToday: Bool
    let isOverdue: Bool
    let completed: Bool
    let isBusy: Bool
    var carriedOverLabel: String? = nil
    var allowsReopening = false
    let complete: () -> Void
    @State private var textEditor: TaskEditorModel?
    @State private var recurrenceEditor: TaskEditorModel?
    @State private var dateEditor: TaskEditorModel?
    @State private var errorText: String?
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()
    @State private var linkDestination: LinkDestination?

    private var box: TaskBoxPresentation { TaskBoxPresentation(row: row, isCompleted: completed) }

    private var canToggleCompletion: Bool {
        !((row.isClosed && !allowsReopening) || completed || isBusy || !store.canAddEvent)
    }

    var body: some View {
        InkTaskRow(
            title: row.text.plainText,
            state: box.state,
            carriedOverLabel: carriedOverLabel,
            segments: InkLinkMapping.segments(from: row.text, entities: store.content.entities),
            openURL: { openLink($0) },
            action: canToggleCompletion ? complete : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if canToggleCompletion, !row.text.spans.contains(where: { $0.target != nil }) {
                complete()
            }
        }
        .accessibilityAction(named: Text(completionActionName)) {
            if canToggleCompletion, !row.text.spans.contains(where: { $0.target != nil }) {
                complete()
            }
        }
        .contextMenu {
            if isToday {
                Button("Metni düzenle", systemImage: "pencil") { textEditor = TaskEditorModel(store: store, row: row) }
                Button("Tarih ver / değiştir", systemImage: "calendar") {
                    dateEditor = TaskEditorModel(store: store, row: row)
                }
                if row.due != nil { Button("Tarihi kaldır") { edit { await $0.setDue(nil) } } }
                Button("Tekrar", systemImage: "repeat") { recurrenceEditor = TaskEditorModel(store: store, row: row) }
                Menu("Öncelik") {
                    Button("Yüksek") { edit { await $0.setPriority(.high) } }
                    Button("Orta") { edit { await $0.setPriority(.medium) } }
                    Button("Düşük") { edit { await $0.setPriority(.low) } }
                    Button("Yok") { edit { await $0.setPriority(nil) } }
                }
                Button("Sil", systemImage: "trash", role: .destructive) {
                    deleteConfirmation.request(.pending)
                }
            }
        }
        .destructiveConfirmationDialog("Görevi sil?", confirmation: $deleteConfirmation) { _ in
            edit { await $0.delete() }
        }
        .sheet(item: $textEditor) { model in
            NavigationStack { TaskTextEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $recurrenceEditor) { model in
            NavigationStack { TaskRecurrenceEditor(model: model) }.presentationDetents([.medium, .large])
        }
        .sheet(item: $dateEditor) { model in
            NavigationStack { TaskDateEditor(model: model) }.frame(minWidth: 320, minHeight: 200)
                .presentationDetents([.medium, .large])
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
        .overlay(alignment: .bottomLeading) {
            if let error = errorText {
                InfoBand(kind: .error, verbatim: error)
            }
        }
    }

    private var completionActionName: LocalizedStringKey {
        LocalizedStringKey(row.isClosed && allowsReopening ? "Görevi yeniden aç" : "Görevi tamamla")
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

    private func edit(_ operation: @escaping (TaskEditorModel) async -> Bool) {
        Task {
            let model = TaskEditorModel(store: store, row: row)
            await model.load()
            if model.target != nil { _ = await operation(model) }
            errorText = model.errorText
        }
    }

    private struct LinkDestination: Identifiable {
        let name: String
        let path: String?
        let entity: EntitySummary?
        var id: String { path ?? name }
    }
}
