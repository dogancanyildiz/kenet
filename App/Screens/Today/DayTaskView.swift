import SwiftUI
import VaultFormat

struct DayTaskView: View {
    let store: IndexStore
    let row: TaskRow
    let isToday: Bool
    let isOverdue: Bool
    let completed: Bool
    let isBusy: Bool
    /// Day used for due-date copy; defaults to today so other screens keep compiling.
    var day: CalendarDate = LocalDay.today()
    var carriedOverLabel: String? = nil
    var allowsReopening = false
    var entityIndex: [String: EntitySummary] = [:]
    let complete: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @State private var textEditor: TaskEditorModel?
    @State private var recurrenceEditor: TaskEditorModel?
    @State private var dateEditor: TaskEditorModel?
    @State private var errorText: String?
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()
    @State private var linkDestination: EntityLinkDestination?

    private var box: TaskBoxPresentation { TaskBoxPresentation(row: row, isCompleted: completed) }

    private var secondary: DayTaskSecondaryPresentation {
        DayTaskSecondaryPresentation(
            row: row, isCarriedOver: isOverdue, carriedOverLabel: carriedOverLabel,
            today: day, locale: locale, calendar: calendar)
    }

    private var canToggleCompletion: Bool {
        !((row.isClosed && !allowsReopening) || completed || isBusy || !store.canAddEvent)
    }

    private var completionLabel: LocalizedStringKey {
        LocalizedStringKey(row.isClosed && allowsReopening ? "Görevi yeniden aç" : "Görevi tamamla")
    }

    var body: some View {
        let facts = secondary
        VStack(alignment: .leading, spacing: 4) {
            InkTaskRow(
                title: row.text.plainText,
                state: box.state,
                carriedOverLabel: facts.carriedOverLabel,
                dueLabel: facts.dueLabel,
                recurrenceLabel: facts.recurrenceLabel,
                showsUnknownRecurrence: facts.showsUnknownRecurrence,
                showsLowPriority: facts.showsLowPriority,
                segments: InkLinkMapping.segments(
                    from: row.text,
                    entitiesByID: entityIndex.isEmpty
                        ? InkLinkMapping.entityIndex(store.content.entities) : entityIndex),
                openURL: { openLink($0) },
                action: canToggleCompletion ? complete : nil,
                accessibilityLabelKey: completionLabel
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if canToggleCompletion, !row.text.spans.contains(where: { $0.target != nil }) {
                    complete()
                }
            }
            .accessibilityAction(named: Text(completionLabel)) {
                if canToggleCompletion, !row.text.spans.contains(where: { $0.target != nil }) {
                    complete()
                }
            }
            .contextMenu {
                if isToday {
                    Button("Metni düzenle", systemImage: "pencil") {
                        textEditor = TaskEditorModel(store: store, row: row)
                    }
                    Button("Tarih ver / değiştir", systemImage: "calendar") {
                        dateEditor = TaskEditorModel(store: store, row: row)
                    }
                    if row.due != nil { Button("Tarihi kaldır") { edit { await $0.setDue(nil) } } }
                    Button("Tekrar", systemImage: "repeat") {
                        recurrenceEditor = TaskEditorModel(store: store, row: row)
                    }
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
            if let error = errorText {
                InfoBand(kind: .error, verbatim: error)
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
        .entityLinkSheet($linkDestination, store: store)
    }

    private func openLink(_ url: URL) {
        linkDestination = EntityLinkDestination.from(url: url, entities: store.content.entities)
    }

    private func edit(_ operation: @escaping (TaskEditorModel) async -> Bool) {
        Task {
            let model = TaskEditorModel(store: store, row: row)
            await model.load()
            if model.target != nil { _ = await operation(model) }
            errorText = model.errorText
        }
    }
}
