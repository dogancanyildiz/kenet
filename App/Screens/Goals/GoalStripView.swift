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
        // Today lists only daily goals so the section counter matches ``countedGoalIDs``.
        let daily = dailyGoals
        if !daily.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: String(localized: "Hedefler"),
                    counter: counter
                        ?? "\(daily.filter { model.isComplete(for: $0) }.count)/\(daily.count)"
                )
                ForEach(daily, id: \.id) { goal in
                    goalRow(goal)
                }
                if model.isLoading {
                    InkProgress(kind: .indeterminate(label: "İndeks güncelleniyor…"))
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

    private func ordered(_ goals: [GoalDefinition]) -> [GoalDefinition] {
        goals.sorted {
            if model.isComplete(for: $0) != model.isComplete(for: $1) { return !model.isComplete(for: $0) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder private func goalRow(_ goal: GoalDefinition) -> some View {
        let status = model.status(for: goal)
        let progress = progressValue(for: goal, status: status)
        InkGoalRow(
            name: goal.name,
            progress: progress,
            isBoolean: goal.kind != .number,
            valueText: valueText(for: goal),
            onIncrement: model.canEdit
                ? {
                    if goal.kind == .boolean || goal.kind == .milestone {
                        Task {
                            if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                        }
                    } else {
                        Task { await increment(goal) }
                    }
                } : nil
        )
        .opacity(model.isComplete(for: goal) ? 0.7 : 1)
        .onLongPressGesture {
            if goal.kind == .number {
                editing = GoalValueModel(dayModel: model, goal: goal)
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
        let amount: Double = if case .number(let number) = model.value(for: goal) { number } else { 0 }
        let unit = goal.unit.map { " \($0)" } ?? ""
        let done = amount.formatted(.number.locale(locale))
        let target = goal.target.formatted(.number.locale(locale))
        return "\(done) / \(target)\(unit)"
    }

    private func increment(_ goal: GoalDefinition) async {
        let current: Double = if case .number(let number) = model.value(for: goal) { number } else { 0 }
        if await model.set(goal, value: .number(current + 1)) {
            geofences?.clearLockedMarkNotice()
        }
    }
}
