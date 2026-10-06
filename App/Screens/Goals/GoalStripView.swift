import GoalTracking
import SwiftUI
import VaultFormat

struct GoalStripView: View {
    @Environment(GeofenceService.self) private var geofences: GeofenceService?
    @State private var model: GoalDayModel
    @State private var editing: GoalValueModel?
    init(store: IndexStore, day: CalendarDate) { _model = State(initialValue: GoalDayModel(store: store, day: day)) }

    var body: some View {
        if !model.goals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hedefler").font(.headline).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(orderedGoals, id: \.id) { goal in
                            Button {
                                if goal.kind == .boolean {
                                    Task {
                                        if await model.toggle(goal) { geofences?.clearLockedMarkNotice() }
                                    }
                                } else {
                                    editing = GoalValueModel(dayModel: model, goal: goal)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(
                                            systemName: model.isComplete(for: goal) ? "checkmark.circle.fill" : "circle"
                                        )
                                        Text(verbatim: goal.name).font(.headline)
                                    }
                                    if goal.kind == .number {
                                        let value = model.value(for: goal)
                                        let amount: Double = if case .number(let number) = value { number } else { 0 }
                                        Text(
                                            verbatim: amount.formatted() + " / " + goal.target.formatted() + " "
                                                + (goal.unit ?? "")
                                        )
                                        .font(.subheadline)
                                    } else {
                                        Text(model.isComplete(for: goal) ? "Yapıldı" : "İşaretle").font(.subheadline)
                                    }
                                    if goal.period != .day {
                                        GoalProgressLabel(goal: goal, status: model.status(for: goal))
                                    }
                                }
                                .padding(12).frame(minWidth: 130, alignment: .leading)
                                .background(
                                    model.isComplete(for: goal)
                                        ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .foregroundStyle(model.isComplete(for: goal) ? Color.secondary : Color.primary)
                            }.buttonStyle(.plain).disabled(!model.canEdit)
                        }
                    }
                }
                if model.isLoading { ProgressView() }
                if let error = model.errorText { Text(verbatim: error).font(.caption).foregroundStyle(.secondary) }
                if let notice = geofences?.lockedMarkNotice {
                    Text(verbatim: notice).font(.caption).foregroundStyle(.secondary)
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
    private var orderedGoals: [GoalDefinition] {
        model.goals.sorted {
            if model.isComplete(for: $0) != model.isComplete(for: $1) { return !model.isComplete(for: $0) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
