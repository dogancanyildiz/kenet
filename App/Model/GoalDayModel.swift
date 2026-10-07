import Foundation
import GoalTracking
import Observation
import VaultFormat
import VaultStore

/// Shares day editing with the strip and historical records. Full history keeps streaks uncapped.
@MainActor @Observable
final class GoalDayModel {
    let store: IndexStore
    let day: CalendarDate
    private let root: URL?
    private(set) var logs: [String: [GoalLog]]
    private(set) var isLoading = false
    private(set) var isWriting = false
    private(set) var errorText: String?
    private(set) var hasLoaded = false
    private var pendingLoad = false

    init(store: IndexStore, day: CalendarDate) {
        self.store = store
        self.day = day
        root = store.vaultURL
        logs = store.content.goalLogs
    }

    var goals: [GoalDefinition] { store.content.goals }
    var canEdit: Bool {
        root != nil && root == store.vaultURL && hasLoaded && !isLoading && !isWriting && store.canAddEvent
    }
    func value(for goal: GoalDefinition) -> GoalValue? { logs[goal.key]?.last { $0.day == day }?.value }
    func status(for goal: GoalDefinition) -> GoalStatus {
        GoalProgress.compute(definition: goal, logs: logs[goal.key] ?? [], today: day)
    }
    func isComplete(for goal: GoalDefinition) -> Bool {
        if goal.kind == .milestone { return status(for: goal).completionDate != nil }
        return switch (goal.kind, value(for: goal)) {
        case (.boolean, .boolean(let done)): done
        case (.number, .number(let amount)): amount >= goal.target
        default: false
        }
    }

    func load() async {
        guard root == store.vaultURL else { return }
        if isLoading || isWriting {
            pendingLoad = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            repeat {
                pendingLoad = false
                let revision = store.lastUpdated
                let history = try await store.goalHistory()
                guard root == store.vaultURL else { return }
                logs = history
                hasLoaded = true
                errorText = nil
                pendingLoad = pendingLoad || revision != store.lastUpdated
            } while pendingLoad
        } catch { errorText = DayEditError.message(for: error) }
    }

    @discardableResult
    func toggle(_ goal: GoalDefinition) async -> Bool {
        guard goal.kind != .number else { return false }
        if goal.kind == .milestone, let completed = status(for: goal).completionDate, completed != day { return false }
        return await set(goal, value: value(for: goal) == .boolean(true) ? nil : .boolean(true))
    }

    @discardableResult
    func set(_ goal: GoalDefinition, value: GoalValue?) async -> Bool {
        guard canEdit, goals.contains(goal), value?.isValid != false else { return false }
        if let value {
            switch (goal.kind, value) {
            case (.boolean, .boolean), (.milestone, .boolean), (.number, .number): break
            default: return false
            }
        }
        if goal.kind == .milestone, value == .boolean(true),
            logs[goal.key, default: []].contains(where: {
                $0.day.year == day.year && $0.day != day && $0.value == .boolean(true)
            })
        {
            return false
        }
        isWriting = true
        defer { isWriting = false }
        errorText = nil
        do { try await store.setGoal(on: day, key: goal.key, value: value) } catch {
            errorText = DayEditError.message(for: error)
            guard case VaultStoreError.indexUpdateFailed = error else { return false }
        }
        // Also reflect saved-but-unindexed bytes locally, so a second tap cannot repeat the first edit.
        logs[goal.key, default: []].removeAll { $0.day == day }
        if let value { logs[goal.key, default: []].append(GoalLog(day: day, value: value)) }
        isWriting = false
        if pendingLoad && errorText == nil { await load() }
        return true
    }
}
