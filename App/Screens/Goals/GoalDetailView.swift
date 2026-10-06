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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeadline(title: goal.name, byline: GoalLabelsCopy.periodTitle(goal.period))

                progressBlock(status: status)

                if goal.kind != .milestone {
                    section(title: String(localized: "Son 12 hafta")) {
                        GoalHeatmap(goal: goal, logs: history.logs[goal.key] ?? [], today: history.day) {
                            day in
                            Task { await edit(day) }
                        }
                        .disabled(!history.canEdit)
                    }
                }

                section(title: String(localized: "Tanım")) {
                    definitionBlock
                        .padding(12)
                        .inkSurface()
                }
                .disabled(!store.canAddEvent)

                section(title: String(localized: "Geçmiş kayıtlar")) {
                    historyBlock
                }

                if let error = history.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                if history.isLoading {
                    InkProgress(kind: .indeterminate(label: "Yükleniyor…"))
                }
            }
            .padding(.horizontal, InkSpacing.margin)
            .padding(.vertical, 12)
            .inkPageColumn()
        }
        .inkPage()
        .goalDetailInlineTitle()
        .toolbar { SearchButton() }
        .task(id: store.lastUpdated) { await history.load() }
        .sheet(item: $editing, onDismiss: { Task { await history.load() } }) { model in
            NavigationStack { GoalValueEditor(model: model) }
        }
        .sheet(item: $field) { field in
            NavigationStack { GoalFieldEditor(store: store, goal: goal, field: field) }
        }
    }

    @ViewBuilder
    private func progressBlock(status: GoalStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if goal.kind == .milestone {
                LargeNumberText(
                    verbatim: status.completionDate == nil ? "—" : "1")
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
                        kind: .determinate(
                            completed: Int(year.done.rounded()),
                            total: max(1, Int(year.target.rounded())),
                            label: "Yıllık ilerleme"))
                }
                HStack(spacing: 16) {
                    labeledValue(String(localized: "Güncel zincir"), status.streak.formatted())
                    labeledValue(String(localized: "En uzun seri"), status.longestStreak.formatted())
                }
            }
        }
    }

    private var definitionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            definitionRow(.name, value: goal.name)
            Button {
                field = .period
            } label: {
                definitionLabel(
                    GoalLabelsCopy.fieldTitle(.period), value: GoalLabelsCopy.periodTitle(goal.period))
            }
            .buttonStyle(.plain)
            .disabled(goal.kind == .milestone)
            Button {
                field = .kind
            } label: {
                definitionLabel(
                    GoalLabelsCopy.fieldTitle(.kind), value: GoalLabelsCopy.kindTitle(goal.kind))
            }
            .buttonStyle(.plain)
            .disabled(goal.kind == .milestone)
            if goal.kind != .milestone {
                definitionRow(.target, value: goal.target.formatted())
            }
            definitionRow(.unit, value: goal.unit ?? "")
            definitionLabel(String(localized: "Anahtar"), value: goal.key)
                .foregroundStyle(Color.ink.secondaryText)
        }
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

    private func definitionRow(_ field: GoalEditableField, value: String) -> some View {
        Button {
            self.field = field
        } label: {
            definitionLabel(GoalLabelsCopy.fieldTitle(field), value: value)
        }
        .buttonStyle(.plain)
    }

    private func definitionLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            Spacer()
            Text(verbatim: value)
                .font(.ink.content)
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

enum GoalLabelsCopy {
    static func periodTitle(_ period: GoalPeriod) -> String {
        switch period {
        case .day: String(localized: "Günlük hedef")
        case .week: String(localized: "Haftalık")
        case .year: String(localized: "Yıllık")
        }
    }

    static func kindTitle(_ kind: GoalKind) -> String {
        switch kind {
        case .boolean: String(localized: "Evet / hayır")
        case .number: String(localized: "Sayı")
        case .milestone: String(localized: "Kilometre taşı")
        }
    }

    static func fieldTitle(_ field: GoalEditableField) -> String {
        switch field {
        case .name: String(localized: "Ad")
        case .period: String(localized: "Dönem")
        case .kind: String(localized: "Tür")
        case .target: String(localized: "Hedef miktar")
        case .unit: String(localized: "Birim (isteğe bağlı)")
        }
    }
}

extension View {
    @ViewBuilder
    fileprivate func goalDetailInlineTitle() -> some View {
        #if os(iOS)
            self.navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }
}
