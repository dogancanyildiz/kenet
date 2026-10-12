import Foundation
import GoalTracking
import Observation
import VaultFormat
import VaultStore

/// Steps of the "close the day" flow, in order. Empty task and goal steps are left out of one
/// opening; the journal step stays.
enum CloseDayStep: Int, CaseIterable, Sendable {
    case tasks
    case goals
    case journal
}

/// One opening of the sheet. The row starts on the first step that has something to do; a journal
/// reminder starts on the journal step.
struct CloseDayRoute: Identifiable {
    let id = UUID()
    var step: CloseDayStep
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
    /// Only on Today, while a task or daily goal is still open, or while today has no journal
    /// entry yet. Otherwise the row takes no space. A past day never offers it.
    static func isOffered(isToday: Bool, presentation: TodayPresentation, hasJournal: Bool) -> Bool {
        isToday
            && (presentation.remainingTaskCount > 0 || presentation.remainingGoalCount > 0 || !hasJournal)
    }

    /// A journal entry is written prose: the same test as the page's journal preview, so the row
    /// is offered exactly while the page says "Günlük yazısı ekle…". Headings alone (an Obsidian
    /// template) and a blank Journal are not an entry.
    static func hasJournal(_ day: DaySummary) -> Bool {
        day.journal.contains { $0.headingLevel == nil }
    }
}

extension NotificationNavigationRequest {
    /// Set when this tap opens today's close-the-day flow, on its journal step: the evening
    /// journal reminder. The day in its identifier is not the flow's day, so a reminder left from
    /// yesterday opens today's flow too.
    var closeDayRequestID: UUID? { destination == .journal ? id : nil }
}

/// One reminder tap opens the flow once. The tap stays the service's latest request until the
/// next one, and Today can be built again for it (a Mac section switch, a second window).
@MainActor
enum CloseDayReminder {
    private static var opened: UUID?

    /// True the first time a request is seen; every later call for it is false.
    static func claim(_ request: UUID?) -> Bool {
        guard let request, request != opened else { return false }
        opened = request
        return true
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

/// State of the flow. Nothing is written until the user applies a choice, marks a goal or writes
/// a sentence; the flow itself leaves no mark in the vault.
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
    /// Steps of this opening. Empty task and goal steps are omitted; the journal step stays.
    let steps: [CloseDayStep]
    private(set) var step: CloseDayStep
    private(set) var report: CloseDayReport?
    private(set) var isApplying = false
    /// The sentence waiting to be appended. A paste may contain line breaks; they are kept.
    var sentence = ""
    private(set) var journalNotice: String?
    private(set) var journalError: String?
    private var choices: [String: CloseDayChoice] = [:]
    /// The vault the flow was opened on: a sentence typed for it never lands in another one.
    private let root: URL?
    /// The store's Journal append; tests replace it to fail or wait the way a real write can.
    private let append: @MainActor (CalendarDate, [String]) async throws -> Void

    /// The day's candidate rows (``IndexStore/computeDayTasks(on:)``), refreshed after each write.
    private var rows: [TaskRow]

    /// - Parameter tasks: the day's rows as Today drew them; the steps are decided from them.
    init(
        store: IndexStore, today: CalendarDate, tasks: [TaskRow], step: CloseDayStep = .tasks,
        calendar: Calendar = .autoupdatingCurrent,
        append: (@MainActor (CalendarDate, [String]) async throws -> Void)? = nil
    ) {
        self.store = store
        self.today = today
        self.calendar = calendar
        root = store.vaultURL
        self.append = append ?? { try await store.appendToJournal(on: $0, lines: $1) }
        goals = GoalDayModel(store: store, day: today)
        let statuses = TodayPresentation.goalStatuses(
            goals: store.content.goals, logs: store.content.goalLogs, day: today)
        pendingGoalIDs = store.content.goals
            .filter { $0.period == .day && statuses[$0.key]?.progress.isComplete != true }
            .map(\.id)
        rows = tasks
        let open = Self.openTasks(tasks, today: today)
        var included: [CloseDayStep] = []
        if !open.isEmpty { included.append(.tasks) }
        if !pendingGoalIDs.isEmpty { included.append(.goals) }
        included.append(.journal)
        steps = included
        self.step = included.contains(step) ? step : included[0]
    }

    /// Carried-over tasks, today's tasks and undated tasks written today; closed ones are gone.
    var tasks: [TaskRow] { Self.openTasks(rows, today: today) }

    /// Asks the index for the day's rows again; a reload cancelled or outlived by its vault leaves
    /// them as they were. The steps stay as the flow opened.
    func loadTasks() async {
        if let loaded = try? await store.computeDayTasks(on: today) { rows = loaded }
    }

    private static func openTasks(_ rows: [TaskRow], today: CalendarDate) -> [TaskRow] {
        let groups = TaskGroups(rows: rows, on: today, isToday: true)
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

    /// Blank or whitespace-only text writes nothing and creates no file. Another vault selected
    /// since the flow opened is not written either.
    var canWriteSentence: Bool {
        !isApplying && store.canAddEvent && store.vaultURL == root && !sentence.allSatisfy(\.isWhitespace)
    }

    /// While a write is in flight the sheet stays, so that its result is seen.
    var canClose: Bool { !isApplying }

    /// 1-based place of the current step among the steps this opening actually shows.
    var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }
    var stepCount: Int { steps.count }
    var canAdvance: Bool { (steps.firstIndex(of: step) ?? 0) + 1 < steps.count }
    var canGoBack: Bool { (steps.firstIndex(of: step) ?? 0) > 0 }

    func advance() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        step = steps[index + 1]
    }

    func back() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }

    /// Appends the sentence to the journal of the day the flow was opened on. A second call in the
    /// same opening appends another block. An empty sentence does not write. A write already in
    /// flight is not started again, and an index failure is not retried: the file was written.
    func writeSentence() async {
        guard canWriteSentence else { return }
        let text = sentence
        isApplying = true
        defer { isApplying = false }
        // Cleared first so that a second sentence's notice is announced again.
        journalNotice = nil
        journalError = nil
        do {
            try await append(today, [text])
            if sentence == text { sentence = "" }
            journalNotice = String(localized: "Cümle günlüğe eklendi.")
        } catch VaultStoreError.indexUpdateFailed {
            // The bytes are in the file: leaving the sentence would offer to write it twice.
            if sentence == text { sentence = "" }
            journalError = String(localized: "Değişiklik kaydedildi, indeks güncellenemedi.")
        } catch {
            // Nothing was written; the sentence stays for another try.
            journalError = Self.journalMessage(for: error)
        }
    }

    /// The sentence is the user's; a refusal names the file, not the text that was typed.
    static func journalMessage(for error: any Error) -> String {
        switch error {
        case EditError.sectionNotWritable, EditError.contentNotRepresentable:
            String(
                localized:
                    "Bugünün dosyasındaki günlük bölümüne eklenemiyor. Kapanmamış kod bloğunu ya da dosyanın başındaki alanları kontrol et."
            )
        case EditError.readOnlyDocument:
            String(localized: "Bugünün dosyası okunamadığı için yazılmadı. Dosyanın kodlamasını kontrol et.")
        default:
            DayEditError.message(for: error)
        }
    }

    /// Writes the chosen tasks only. Each one is read again right before its own write; a task
    /// that changed since it was listed is counted and skipped, the rest still write.
    func apply() async {
        guard canApply else { return }
        isApplying = true
        defer { isApplying = false }
        // Choices are matched against the rows as they are now: an outside edit since the list was
        // drawn must not carry a choice onto another task.
        await loadTasks()
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
        // The list shows what is left as soon as the report does.
        await loadTasks()
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
