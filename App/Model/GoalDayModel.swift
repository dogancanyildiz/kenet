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
    private(set) var logs: [String: [GoalLog]] {
        didSet { forgetStatuses(changedFrom: oldValue) }
    }
    private(set) var isLoading = false
    private(set) var isWriting = false
    private(set) var errorText: String?
    private(set) var hasLoaded = false
    private var pendingLoad = false
    /// Edits made here, by goal key, that the screen's goal-status answer may not show yet.
    private var unanswered: [String: UnansweredEdit] = [:]
    /// The latest revision a screen's goal-status answer was asked at.
    @ObservationIgnored private var answeredRevision: Int?
    /// The store's `lastUpdated` this model last saw, and its count (see `currentRevision()`).
    @ObservationIgnored private var seenUpdate: Date?
    @ObservationIgnored private var seenRevision = 0

    init(store: IndexStore, day: CalendarDate) {
        self.store = store
        self.day = day
        root = store.vaultURL
        logs = store.content.goalLogs
    }

    var goals: [GoalDefinition] { store.content.goals }
    /// Whether this model edits the vault at `url` (a model outlives a vault switch on its screen).
    func belongs(to url: URL?) -> Bool { root == url }
    var canEdit: Bool {
        root != nil && root == store.vaultURL && hasLoaded && !isLoading && !isWriting && store.canAddEvent
    }
    func value(for goal: GoalDefinition) -> GoalValue? { logs[goal.key]?.last { $0.day == day }?.value }
    /// Today's own record says yes (a period already met by earlier days does not count).
    func isMarkedToday(_ goal: GoalDefinition) -> Bool { value(for: goal) == .boolean(true) }
    /// Statuses by goal id, each with the definition it was computed for: a draw reads a goal's
    /// status many times (order, count, row), and the full history is computed once per change.
    @ObservationIgnored private var computedStatuses: [String: (goal: GoalDefinition, status: GoalStatus)] = [:]
    /// How many statuses this model computed from its history (tests count them per draw).
    @ObservationIgnored private(set) var statusComputations = 0
    func status(for goal: GoalDefinition) -> GoalStatus {
        // Read before the kept status too: a view drawn from a status follows the history.
        let history = logs[goal.key]
        if let kept = computedStatuses[goal.id], kept.goal == goal { return kept.status }
        statusComputations += 1
        let status = GoalProgress.compute(definition: goal, logs: history ?? [], today: day)
        computedStatuses[goal.id] = (goal, status)
        return status
    }

    /// Drops the statuses of the keys whose history changed; a reload with the same history keeps all.
    private func forgetStatuses(changedFrom old: [String: [GoalLog]]) {
        let changed = Set(old.keys).union(logs.keys).filter { old[$0] != logs[$0] }
        guard !changed.isEmpty else { return }
        computedStatuses = computedStatuses.filter { !changed.contains($0.value.goal.key) }
    }
    func isComplete(for goal: GoalDefinition) -> Bool {
        if goal.kind == .milestone { return status(for: goal).completionDate != nil }
        return switch (goal.kind, value(for: goal)) {
        case (.boolean, .boolean(let done)): done
        case (.number, .number(let amount)): amount >= goal.target
        default: false
        }
    }

    /// The status a screen draws for `goal`: its goal-status `answer`, unless an edit made here may
    /// be missing from it; then this model's own, which has the edit from the moment it is made.
    func shownStatus(for goal: GoalDefinition, answer: GoalStatus?) -> GoalStatus {
        guard unanswered[goal.key] == nil, let answer else { return status(for: goal) }
        return answer
    }

    /// `answer` (statuses by goal key, the first definition by name for a key) with each goal an
    /// edit made here may be missing from drawn from this model, by the same rule.
    func shownStatuses(_ answer: [String: GoalStatus]) -> [String: GoalStatus] {
        var shown = answer
        for key in unanswered.keys {
            if let goal = goals.first(where: { $0.key == key }) { shown[key] = status(for: goal) }
        }
        return shown
    }

    /// The store's published state as a count that only goes up, nil with no vault open. Taken
    /// when a screen asks for statuses and when an edit is written: `lastUpdated` only moves to a
    /// newer publish, so a changed value is always a later one, whatever the wall clock does.
    func currentRevision() -> Int? {
        guard let updated = store.lastUpdated else { return nil }
        if updated != seenUpdate {
            seenUpdate = updated
            seenRevision += 1
        }
        return seenRevision
    }

    /// A goal-status answer asked at `revision` (`currentRevision()` when the query started) is on
    /// screen: it shows every edit published by then, so those goals draw from it again.
    func answerShown(askedAt revision: Int?) {
        guard let revision else { return }
        if answeredRevision.map({ $0 < revision }) ?? true { answeredRevision = revision }
        dropAnsweredEdits()
    }

    private func dropAnsweredEdits() {
        guard let answeredRevision else { return }
        let answered = unanswered.filter { $0.value.isShown(byAnswerAskedAt: answeredRevision) }.keys
        for key in answered { unanswered[key] = nil }
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
        // Drawn at once, before the write ends; taken back if nothing was saved. Saved-but-unindexed
        // bytes stay reflected, so a second tap cannot repeat the first edit.
        let previous = logs[goal.key]
        let previousEdit = unanswered[goal.key]
        logs[goal.key, default: []].removeAll { $0.day == day }
        if let value { logs[goal.key, default: []].append(GoalLog(day: day, value: value)) }
        unanswered[goal.key] = UnansweredEdit()
        do {
            try await store.setGoal(on: day, key: goal.key, value: value)
            unanswered[goal.key] = UnansweredEdit(revision: currentRevision() ?? 0)
        } catch {
            errorText = DayEditError.message(for: error)
            guard case VaultStoreError.indexUpdateFailed = error else {
                // An earlier edit still waiting for its answer keeps waiting.
                logs[goal.key] = previous
                unanswered[goal.key] = previousEdit
                return false
            }
            unanswered[goal.key] = UnansweredEdit(revision: currentRevision() ?? 0, isIndexed: false)
        }
        dropAnsweredEdits()
        isWriting = false
        if pendingLoad && errorText == nil { await load() }
        return true
    }
}

/// An edit a screen's goal-status answer may not show yet.
private struct UnansweredEdit {
    /// `currentRevision()` once the edit was written; nil while it is being written.
    var revision: Int?
    /// Saved but not indexed: only an answer asked after a later publish can show it.
    var isIndexed = true

    func isShown(byAnswerAskedAt answered: Int) -> Bool {
        guard let revision else { return false }
        return isIndexed ? answered >= revision : answered > revision
    }
}
