import Foundation
import GoalTracking
import Observation
import VaultFormat
import VaultStore

/// Steps of the "close the day" flow, in order.
enum CloseDayStep: Int, CaseIterable, Sendable {
    case tasks
    case goals

    var previous: CloseDayStep? { CloseDayStep(rawValue: rawValue - 1) }
    var next: CloseDayStep? { CloseDayStep(rawValue: rawValue + 1) }
}

/// What happens to one open task. `keep` writes nothing.
enum CloseDayChoice: Hashable, Sendable {
    case keep
    case done
    case tomorrow
    case nextWeek
}

/// The Today row that opens the flow.
enum CloseDayEntry {
    /// Only on Today, and only while something is still open; otherwise the row takes no space.
    static func isOffered(isToday: Bool, presentation: TodayPresentation) -> Bool {
        isToday && (presentation.remainingTaskCount > 0 || presentation.remainingGoalCount > 0)
    }
}

/// Outcome of one "Uygula": completions counted here, moves by ``TaskMoveReport``.
struct CloseDayReport: Equatable, Sendable {
    var completed = 0
    /// Not completed because the task changed or disappeared since it was listed.
    var completionUnchanged = 0
    /// Not completed for any other reason.
    var completionFailed = 0
    var moves = TaskMoveReport()
    var failureText: String?

    var isPartial: Bool { completionUnchanged > 0 || completionFailed > 0 || moves.isPartial }

    func text(locale: Locale) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        var parts: [String] = []
        if completed > 0 {
            parts.append(String(localized: "\(completed) görev tamamlandı", bundle: bundle, locale: locale))
        }
        if completionUnchanged > 0 {
            parts.append(
                String(
                    localized: "\(completionUnchanged) görev değişmiş olduğu için tamamlanmadı",
                    bundle: bundle, locale: locale))
        }
        if completionFailed > 0 {
            parts.append(
                String(localized: "\(completionFailed) görev tamamlanamadı", bundle: bundle, locale: locale))
        }
        if let moved = moves.text(locale: locale) { parts.append(moved) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }
}

/// State of the flow. Nothing is written until the user applies a choice or marks a goal; the
/// flow itself leaves no mark in the vault.
@MainActor @Observable
final class CloseDayModel {
    let store: IndexStore
    let today: CalendarDate
    /// Decides where "Haftaya" lands, the same way the task menu does.
    private let calendar: Calendar
    /// The Today strip's model: goals are marked through the same write path.
    let goals: GoalDayModel
    /// Daily goals that were unmarked when the flow opened. A goal marked here stays listed (and
    /// can be unmarked) until the flow is opened again.
    let pendingGoalIDs: [String]
    private(set) var step: CloseDayStep
    private(set) var report: CloseDayReport?
    private(set) var isApplying = false
    private var choices: [String: CloseDayChoice] = [:]

    init(
        store: IndexStore, today: CalendarDate, step: CloseDayStep = .tasks,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.store = store
        self.today = today
        self.calendar = calendar
        self.step = step
        goals = GoalDayModel(store: store, day: today)
        let statuses = TodayPresentation.goalStatuses(
            goals: store.content.goals, logs: store.content.goalLogs, day: today)
        pendingGoalIDs = store.content.goals
            .filter { $0.period == .day && statuses[$0.key]?.progress.isComplete != true }
            .map(\.id)
    }

    /// Carried-over tasks, today's tasks and undated tasks written today; closed ones are gone.
    var tasks: [TaskRow] {
        let groups = TaskGroups(rows: store.content.tasks, on: today, isToday: true)
        return groups.overdue + groups.dated + groups.created
    }

    var pendingGoals: [GoalDefinition] {
        let ids = Set(pendingGoalIDs)
        return goals.goals.filter { ids.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func choice(for row: TaskRow) -> CloseDayChoice { choices[Self.key(row)] ?? .keep }

    func choose(_ choice: CloseDayChoice, for row: TaskRow) {
        guard !isApplying else { return }
        choices[Self.key(row)] = choice == .keep ? nil : choice
    }

    var canApply: Bool {
        !isApplying && store.canAddEvent && tasks.contains { choice(for: $0) != .keep }
    }

    /// While tasks are being written the sheet stays, so that their report is seen.
    var canClose: Bool { !isApplying }

    func advance() { if let next = step.next { step = next } }
    func back() { if let previous = step.previous { step = previous } }

    /// Writes the chosen tasks only. Each one is read again right before its own write; a task
    /// that changed since it was listed is counted and skipped, the rest still write.
    func apply() async {
        guard canApply else { return }
        isApplying = true
        defer { isApplying = false }
        let root = store.vaultURL
        let chosen = tasks.map { (row: $0, choice: choice(for: $0)) }
        var result = CloseDayReport()
        for row in chosen.filter({ $0.choice == .done }).map(\.row) {
            // The rows were listed from `root`; another vault may hold a look-alike task.
            guard store.vaultURL == root else {
                result.completionFailed += 1
                continue
            }
            do {
                try await store.completeTask(row, on: today)
                result.completed += 1
            } catch VaultStoreError.indexUpdateFailed {
                result.completed += 1
                if result.failureText == nil {
                    result.failureText = String(localized: "Değişiklik kaydedildi, indeks güncellenemedi.")
                }
            } catch VaultStoreError.staleTarget {
                result.completionUnchanged += 1
            } catch {
                result.completionFailed += 1
                if result.failureText == nil { result.failureText = DayEditError.message(for: error) }
            }
        }
        let destinations: [(CloseDayChoice, TaskMoveDestination)] = [(.tomorrow, .tomorrow), (.nextWeek, .nextWeek)]
        for (choice, destination) in destinations {
            let rows = chosen.filter { $0.choice == choice }.map(\.row)
            guard !rows.isEmpty, let date = TaskMove.date(destination, today: today, calendar: calendar) else {
                continue
            }
            let moved = await TaskMove.apply(rows, to: date, in: store)
            result.moves.moved += moved.moved
            result.moves.unchanged += moved.unchanged
            result.moves.failed += moved.failed
            if result.failureText == nil { result.failureText = moved.failureText }
        }
        choices = [:]
        report = result
    }

    /// A choice belongs to the task as it was listed. A row without a block identifier is named
    /// by its line, so after an outside edit that line may hold another task: the fields keep a
    /// choice from sliding onto it.
    private static func key(_ row: TaskRow) -> String {
        [row.id, row.rawStatus, row.due?.description ?? "", row.sourceText].joined(separator: "\u{0}")
    }
}
