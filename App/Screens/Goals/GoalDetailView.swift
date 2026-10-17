import GoalTracking
import SwiftUI
import VaultFormat

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deletion = DefinitionDeletionModel()
    let store: IndexStore
    private let original: GoalDefinition
    @State private var history: GoalDayModel
    @State private var editing: GoalValueModel?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isEditing = false
    init(store: IndexStore, goal: GoalDefinition, day: CalendarDate = LocalDay.today()) {
        self.store = store
        original = goal
        _history = State(initialValue: GoalDayModel(store: store, day: day))
    }
    private var goal: GoalDefinition { store.content.goals.first { $0.id == original.id } ?? original }
    var body: some View {
        let status = history.status(for: goal)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InkPageTitle(verbatim: goal.name, byline: goal.period.title) {
                    if store.canAddEvent {
                        InkHeaderAction(
                            "Düzenle", systemImage: "pencil", role: .primary, identifier: "button.goal.edit"
                        ) { isEditing = true }
                    }
                    SearchButton()
                }

                progressBlock(status: status)
                    .padding(.horizontal, InkSpacing.margin)

                if GoalValueChart.isShown(for: goal) {
                    section(title: GoalValueChart.title(for: goal, isAccessibilitySize: typeSize.isAccessibilitySize)) {
                        GoalValueChart(goal: goal, logs: history.logs[goal.key] ?? [], today: history.day)
                    }
                    .padding(.horizontal, InkSpacing.margin)
                }

                if goal.kind != .milestone {
                    section(title: String(localized: "Isı haritası")) {
                        GoalHeatmap(goal: goal, logs: history.logs[goal.key] ?? [], today: history.day) {
                            day in
                            Task { await edit(day) }
                        }
                        .disabled(!history.canEdit)
                    }
                    .padding(.horizontal, InkSpacing.margin)
                }

                section(title: String(localized: "Tanım")) {
                    definitionBlock
                }
                .padding(.horizontal, InkSpacing.margin)
                .disabled(!store.canAddEvent)

                section(title: String(localized: "Geçmiş kayıtlar")) {
                    historyBlock
                }
                .padding(.horizontal, InkSpacing.margin)

                if let error = history.errorText {
                    InfoBand(kind: .error, verbatim: error)
                        .padding(.horizontal, InkSpacing.margin)
                }
                if history.isLoading {
                    InkProgress(kind: .indeterminate(label: "Yükleniyor…"))
                        .padding(.horizontal, InkSpacing.margin)
                }
            }
            .padding(.vertical, 12)
            .inkPageColumn()
        }
        .inkPage()
        .inkPageNavigationTitle(verbatim: goal.name)
        .task(id: store.lastUpdated) {
            await history.load()
        }
        .sheet(item: $editing, onDismiss: { Task { await history.load() } }) { model in
            NavigationStack { GoalValueEditor(model: model) }
                .inkAdaptiveSheetPresentation(fitsContent: true, usesPhoneDetents: false)
        }
        .sheet(
            isPresented: $isEditing,
            onDismiss: {
                // "Hedefi sil" closes the form first; the detail goes once the sheet is down.
                if deletion.isDeleted { dismiss() }
            },
            content: {
                NavigationStack { GoalDefinitionForm(store: store, goal: goal, deletion: deletion) }
            }
        )
    }

    @ViewBuilder
    private func progressBlock(status: GoalStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if goal.kind == .milestone {
                GoalProgressLabel(goal: goal, status: status)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LargeNumberText(verbatim: status.progress.done.formatted())
                    Text(verbatim: "/ " + goal.target.formatted())
                        .font(.ink.value)
                        .foregroundStyle(Color.ink.secondaryText)
                    if let unit = goal.unit {
                        Text(verbatim: unit)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
                GoalProgressLabel(goal: goal, status: status)
                if let year = status.yearProgress {
                    InkProgress(
                        kind: .fraction(
                            InkProgressMath.ratio(done: year.done, target: year.target),
                            label: "Yıllık ilerleme"))
                }
                HStack(spacing: 16) {
                    labeledValue(String(localized: "Güncel zincir"), status.streak.formatted())
                    labeledValue(String(localized: "En uzun seri"), status.longestStreak.formatted())
                }
                if goal.period == .day, let score = status.score {
                    Text(verbatim: GoalScoreCopy.sentence(score))
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
        }
    }

    /// Read-only summary; a tap anywhere on it opens the definition form.
    private var definitionBlock: some View {
        Button {
            isEditing = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                definitionLabel(GoalEditableField.name.title, value: goal.name, valueFont: .ink.content)
                definitionLabel(GoalEditableField.period.title, value: goal.period.title, valueFont: .ink.byline)
                definitionLabel(GoalEditableField.kind.title, value: goal.kind.title, valueFont: .ink.byline)
                if goal.kind != .milestone {
                    definitionLabel(
                        GoalEditableField.target.title, value: goal.target.formatted(), valueFont: .ink.value)
                }
                if let unit = goal.unit {
                    definitionLabel(GoalEditableField.unit.title, value: unit, valueFont: .ink.content)
                }
                definitionLabel(String(localized: "Anahtar"), value: goal.key, valueFont: .ink.content)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Hedef tanımını düzenler"))
        .accessibilityIdentifier("button.goal.definition")
    }

    @ViewBuilder
    private var historyBlock: some View {
        let logs = (history.logs[goal.key] ?? []).sorted { $0.day > $1.day }
        if logs.isEmpty {
            Text("Henüz kayıt yok")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(logs, id: \.day) { log in
                    Button {
                        Task { await edit(log.day) }
                    } label: {
                        HStack {
                            Text(LocalDay.instant(for: log.day), format: .dateTime.day().month().year())
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                            Spacer()
                            switch log.value {
                            case .boolean(let value):
                                Text(value ? "Yapıldı" : "İşaretle")
                                    .font(.ink.byline)
                                    .foregroundStyle(Color.ink.text)
                            case .number(let value):
                                Text(verbatim: value.formatted() + " " + (goal.unit ?? ""))
                                    .font(.ink.value)
                                    .foregroundStyle(Color.ink.text)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .disabled(!history.canEdit)
                }
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            content()
        }
    }

    private func definitionLabel(_ title: String, value: String, valueFont: Font) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            Spacer()
            Text(verbatim: value)
                .font(valueFont)
                .foregroundStyle(Color.ink.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .tapTarget()
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            Text(verbatim: value)
                .font(.ink.value)
                .foregroundStyle(Color.ink.text)
        }
    }

    private func edit(_ day: CalendarDate) async {
        let model = GoalDayModel(store: store, day: day)
        await model.load()
        if model.canEdit { editing = GoalValueModel(dayModel: model, goal: goal) }
    }
}
