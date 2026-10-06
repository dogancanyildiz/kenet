import GoalTracking
import SwiftUI
import VaultFormat

struct GoalStripView: View {
    @Environment(GeofenceService.self) private var geofences: GeofenceService?
    @Environment(\.locale) private var locale
    @State private var model: GoalDayModel
    @State private var editing: GoalValueModel?
    private let countedGoalIDs: [String]
    private let counter: String?

    init(
        store: IndexStore, day: CalendarDate, countedGoalIDs: [String] = [],
        counter: String? = nil
    ) {
        _model = State(initialValue: GoalDayModel(store: store, day: day))
        self.countedGoalIDs = countedGoalIDs
        self.counter = counter
    }

    var body: some View {
        let daily = dailyGoals
        let period = periodGoals
        if !daily.isEmpty || !period.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionHeader(
                        title: String(localized: "Hedefler"),
                        counter: counter
                            ?? "\(daily.filter { model.isComplete(for: $0) }.count)/\(daily.count)"
                    )
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel(Text("Hedefler yükleniyor"))
                    }
                }
                ForEach(daily, id: \.id) { goal in
                    goalRow(goal, metaText: nil)
                }
                ForEach(period, id: \.id) { goal in
                    goalRow(goal, metaText: periodMeta(for: goal))
                }
                if let error = model.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                if let notice = geofences?.lockedMarkNotice {
                    InfoBand(kind: .info, verbatim: notice)
                }
            }
            .task(id: model.store.lastUpdated) { await model.load() }
            .sheet(item: $editing) { editor in
                NavigationStack { GoalValueEditor(model: editor) }
                    .onChange(of: editor.isSaved) { _, saved in
                        if saved { geofences?.clearLockedMarkNotice() }
                    }
            }
        }
    }

    private var dailyGoals: [GoalDefinition] {
        let counted = Set(countedGoalIDs)
        let source =
            counted.isEmpty
            ? model.goals.filter { $0.period == .day }
            : model.goals.filter { counted.contains($0.id) }
        return ordered(source)
    }

    private var periodGoals: [GoalDefinition] {
        ordered(model.goals.filter { $0.period != .day })
    }

    private func ordered(_ goals: [GoalDefinition]) -> [GoalDefinition] {
        goals.sorted {
            if model.isComplete(for: $0) != model.isComplete(for: $1) {
                return !model.isComplete(for: $0)
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func periodMeta(for goal: GoalDefinition) -> String {
        let status = model.status(for: goal)
        let periodKey: String.LocalizationValue =
            switch goal.period {
            case .day: "Bu gün"
            case .week: "Bu hafta"
            case .year: "Bu yıl"
            }
        let period = String(localized: periodKey)
        let amount =
            status.progress.done.formatted(.number.locale(locale)) + "/"
            + goal.target.formatted(.number.locale(locale))
        if let unit = goal.unit { return "\(period) \(amount) \(unit)" }
        return "\(period) \(amount)"
    }

    @ViewBuilder private func goalRow(_ goal: GoalDefinition, metaText: String?) -> some View {
        let status = model.status(for: goal)
        let progress = progressValue(for: goal, status: status)
        let complete = model.isComplete(for: goal)
        let isBooleanMark = goal.kind == .boolean || goal.kind == .milestone
        InkGoalRow(
            name: goal.name,
            progress: progress,
            isBoolean: goal.kind != .number,
            valueText: valueText(for: goal),
            metaText: metaText,
            onIncrement: model.canEdit && !(isBooleanMark && complete)
                ? {
                    if isBooleanMark {
                        Task {
                            if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                        }
                    } else {
                        Task { await increment(goal) }
                    }
                } : nil,
            onValueTap: model.canEdit && goal.kind == .number
                ? { editing = GoalValueModel(dayModel: model, goal: goal) } : nil,
            onMarkTap: model.canEdit && isBooleanMark && complete
                ? {
                    Task {
                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                    }
                } : nil,
            showsPlus: !(isBooleanMark && complete),
            incrementLabel: LocalizedStringKey(
                isBooleanMark && complete ? "İşareti kaldır" : "Artır")
        )
        .contextMenu {
            if model.canEdit, goal.kind == .number {
                Button("Miktar gir") { editing = GoalValueModel(dayModel: model, goal: goal) }
            }
            if model.canEdit, isBooleanMark, complete {
                Button("İşareti kaldır") {
                    Task {
                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                    }
                }
            }
        }
        .disabled(!model.canEdit)
    }

    private func progressValue(for goal: GoalDefinition, status: GoalStatus) -> Double {
        if goal.kind == .number { return status.progress.fraction }
        return model.isComplete(for: goal) ? 1 : 0
    }

    private func valueText(for goal: GoalDefinition) -> String? {
        guard goal.kind == .number else { return nil }
        let amount: Double =
            if case .number(let number) = model.value(for: goal) { number } else { 0 }
        let unit = goal.unit.map { " \($0)" } ?? ""
        let done = amount.formatted(.number.locale(locale))
        let target = goal.target.formatted(.number.locale(locale))
        return "\(done) / \(target)\(unit)"
    }

    private func increment(_ goal: GoalDefinition) async {
        let current: Double =
            if case .number(let number) = model.value(for: goal) { number } else { 0 }
        if await model.set(goal, value: .number(current + 1)) {
            geofences?.clearLockedMarkNotice()
        }
    }
}
