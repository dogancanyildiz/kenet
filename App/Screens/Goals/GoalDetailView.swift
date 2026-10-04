import GoalTracking
import SwiftUI
import VaultFormat

struct GoalDetailView: View {
    let store: IndexStore
    private let original: GoalDefinition
    @State private var history: GoalDayModel
    @State private var editing: GoalValueModel?
    @State private var field: GoalEditableField?
    init(store: IndexStore, goal: GoalDefinition) {
        self.store = store
        original = goal
        _history = State(initialValue: GoalDayModel(store: store, day: LocalDay.today()))
    }
    private var goal: GoalDefinition { store.content.goals.first { $0.id == original.id } ?? original }
    var body: some View {
        let status = history.status(for: goal)
        List {
            Section("İlerleme") {
                GoalProgressLabel(goal: goal, status: status)
                if let year = status.yearProgress {
                    ProgressView(value: year.fraction).accessibilityLabel("Yıllık ilerleme")
                }
                if goal.kind != .milestone {
                    LabeledContent("Güncel zincir", value: status.streak.formatted())
                    LabeledContent("En uzun seri", value: status.longestStreak.formatted())
                }
            }
            if goal.kind != .milestone {
                Section("Son 12 hafta") {
                    GoalHeatmap(goal: goal, logs: history.logs[goal.key] ?? [], today: history.day) { day in
                        Task { await edit(day) }
                    }.disabled(!history.canEdit)
                }
            }
            Section("Tanım") {
                definitionRow(.name, value: goal.name)
                Button {
                    field = .period
                } label: {
                    LabeledContent("Dönem") { Text(goal.period.title) }
                }.disabled(goal.kind == .milestone)
                Button {
                    field = .kind
                } label: {
                    LabeledContent("Tür") { Text(goal.kind.title) }
                }.disabled(goal.kind == .milestone)
                if goal.kind != .milestone { definitionRow(.target, value: goal.target.formatted()) }
                definitionRow(.unit, value: goal.unit ?? "")
                LabeledContent("Anahtar", value: goal.key).foregroundStyle(.secondary)
            }.disabled(!store.canAddEvent)
            Section("Geçmiş kayıtlar") {
                ForEach((history.logs[goal.key] ?? []).sorted { $0.day > $1.day }, id: \.day) { log in
                    Button {
                        Task { await edit(log.day) }
                    } label: {
                        HStack {
                            Text(LocalDay.instant(for: log.day), format: .dateTime.day().month().year())
                            Spacer()
                            switch log.value {
                            case .boolean(let value): Text(value ? "Yapıldı" : "İşaretle")
                            case .number(let value): Text(verbatim: value.formatted() + " " + (goal.unit ?? ""))
                            }
                        }
                    }.disabled(!history.canEdit)
                }
                if (history.logs[goal.key] ?? []).isEmpty { Text("Henüz kayıt yok").foregroundStyle(.secondary) }
            }
            if let error = history.errorText { Text(verbatim: error).foregroundStyle(.secondary) }
            if history.isLoading { ProgressView() }
        }
        .navigationTitle(Text(verbatim: goal.name)).toolbar { SearchButton() }
        .task(id: store.lastUpdated) { await history.load() }
        .sheet(item: $editing, onDismiss: { Task { await history.load() } }) { model in
            NavigationStack { GoalValueEditor(model: model) }
        }
        .sheet(item: $field) { field in NavigationStack { GoalFieldEditor(store: store, goal: goal, field: field) } }
    }
    private func definitionRow(_ field: GoalEditableField, value: String) -> some View {
        Button {
            self.field = field
        } label: {
            LabeledContent(field.title) { Text(verbatim: value) }
        }
    }
    private func edit(_ day: CalendarDate) async {
        let model = GoalDayModel(store: store, day: day)
        await model.load()
        if model.canEdit { editing = GoalValueModel(dayModel: model, goal: goal) }
    }
}
