import Foundation
import GoalTracking
import Observation
import Summaries
import VaultFormat
import VaultStore

/// Steps of the weekly review, in order. Every step can be passed without including anything.
enum WeeklyReviewStep: Int, CaseIterable, Sendable {
    case numbers
    case tasks
    case people
    case goals
    case note
    case preview

    var previous: WeeklyReviewStep? { WeeklyReviewStep(rawValue: rawValue - 1) }
    var next: WeeklyReviewStep? { WeeklyReviewStep(rawValue: rawValue + 1) }
}

/// The parts of the output the user turns on and off; the note is its own text.
enum WeeklyReviewSection: CaseIterable, Hashable, Sendable {
    case numbers
    case tasks
    case people
    case goals
}

/// Which week is looked at. The output is always written to the day the review is made on.
enum WeeklyReviewWeek: Hashable, Sendable {
    case current
    case previous

    /// Seven days from the calendar's first weekday. Like ``WeekStart``, a calendar that does not
    /// start on Monday reads as a Sunday week. Only the calendar's week start is used: the days
    /// are vault dates, so no time zone takes part.
    func range(containing today: CalendarDate, calendar: Calendar) -> ClosedRange<CalendarDate> {
        let offset = WeekStart.isMonday(in: calendar) ? today.weekday : (today.weekday + 1) % 7
        let start = today.addingDays(-offset - (self == .previous ? 7 : 0)) ?? today
        return start...(start.addingDays(6) ?? start)
    }
}

/// "Reviewed this week" is a device preference; the vault carries no mark of it.
enum WeeklyReviewPreference {
    static let key = "weeklyReview.reviewedWeekStart"

    static func isReviewed(weekStarting start: CalendarDate, in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: key) == start.description
    }

    static func markReviewed(weekStarting start: CalendarDate, in defaults: UserDefaults) {
        defaults.set(start.description, forKey: key)
    }
}

/// How one goal stood in the reviewed week.
struct WeeklyReviewGoal: Equatable, Sendable, Identifiable {
    enum Standing: Equatable, Sendable {
        /// A daily goal: days at target, out of the week's days up to the review day.
        case days(met: Int, of: Int)
        /// A weekly goal: the week's amount against its target.
        case amount(done: Double, target: Double, unit: String?)
    }

    let id: String
    let name: String
    let standing: Standing
}

/// What the review shows for one week, and the sentences it offers for the journal.
///
/// The sentences are plain text in the user's language. A person is written by name alone: the
/// text goes into Journal as written and is not run through recognition, so link syntax is never
/// produced here.
struct WeeklyReviewContent: Equatable, Sendable {
    static let listedTasks = 3
    static let listedPeople = 3

    let range: ClosedRange<CalendarDate>
    var events = 0
    var completedTasks = 0
    var writtenDays = 0
    var openTaskCount = 0
    /// The first open tasks as plain text.
    var openTasks: [String] = []
    /// Names of the first people whose rhythm (or the fallback threshold) has passed.
    var people: [String] = []
    var goals: [WeeklyReviewGoal] = []

    var hasNumbers: Bool { events > 0 || completedTasks > 0 || writtenDays > 0 }

    /// - Parameters:
    ///   - today: the review day; goal days after it are not counted against the week.
    ///   - tasks: the vault's task rows; the open ones left from the week are picked here.
    static func compute(
        range: ClosedRange<CalendarDate>, today: CalendarDate, input: SummaryInput, tasks: [TaskRow],
        unseen: [UnseenPerson]
    ) -> Self {
        var result = Self(range: range)
        let days = input.days.filter { range.contains($0.date) }
        result.events = days.reduce(0) { $0 + max(0, $1.events) }
        result.writtenDays = Set(days.filter { $0.events > 0 || $0.hasJournal }.map(\.date)).count
        result.completedTasks = input.tasks.filter { $0.status == .done && $0.done.map(range.contains) == true }.count

        // Left from the week: due by its last day, or written in it without a date.
        let open = tasks.filter { row in
            guard !row.isClosed else { return false }
            if let due = row.due { return due <= range.upperBound }
            return row.createdDate.map(range.contains) == true
        }.sorted(by: TasksModel.order)
        result.openTaskCount = open.count
        result.openTasks = open.prefix(listedTasks).map { VaultDisplayText.line($0.text.plainText) }
        // Two people may share a name; the qualifier tells them apart, as in Özetler.
        result.people = unseen.prefix(listedPeople).map { person in
            person.entity.name + (person.entity.qualifier.map { " (" + $0 + ")" } ?? "")
        }

        let last = min(range.upperBound, max(range.lowerBound, today))
        result.goals = input.goals.compactMap { goal -> WeeklyReviewGoal? in
            let definition = goal.definition
            switch definition.period {
            case .day:
                var met = 0
                var count = 0
                var cursor: CalendarDate? = range.lowerBound
                while let day = cursor, day <= last {
                    count += 1
                    let status = GoalProgress.compute(definition: definition, logs: goal.logs, today: day)
                    if status.progress.isComplete { met += 1 }
                    cursor = day.addingDays(1)
                }
                return WeeklyReviewGoal(id: definition.id, name: definition.name, standing: .days(met: met, of: count))
            case .week:
                // The reviewed week's own days: on a Sunday calendar that is not the goal's Monday week.
                var done = 0.0
                var cursor: CalendarDate? = range.lowerBound
                while let day = cursor, day <= last {
                    let logs = goal.logs.filter { $0.day == day }
                    let sum = done + GoalProgress.compute(definition: definition, logs: logs, today: day).progress.done
                    done = sum.isFinite ? sum : Double.greatestFiniteMagnitude
                    cursor = day.addingDays(1)
                }
                return WeeklyReviewGoal(
                    id: definition.id, name: definition.name,
                    standing: .amount(done: done, target: definition.target, unit: definition.unit))
            case .year:
                return nil
            }
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        return result
    }

    // MARK: Sentences

    /// The week and its counts. A count of zero has no sentence; with no count there is no line.
    func numberLines(locale: Locale) -> [String] {
        guard hasNumbers else { return [] }
        let bundle = PresentationLocalization.bundle(locale)
        var lines = [
            String(
                localized: "Hafta: \(range.lowerBound.description) – \(range.upperBound.description)",
                bundle: bundle, locale: locale)
        ]
        if events > 0 { lines.append(String(localized: "\(events) olay", bundle: bundle, locale: locale)) }
        if completedTasks > 0 {
            lines.append(String(localized: "\(completedTasks) görev tamamlandı", bundle: bundle, locale: locale))
        }
        if writtenDays > 0 {
            lines.append(String(localized: "\(writtenDays) günde kayıt var", bundle: bundle, locale: locale))
        }
        return lines
    }

    func taskLines(locale: Locale) -> [String] {
        guard openTaskCount > 0 else { return [] }
        let bundle = PresentationLocalization.bundle(locale)
        var lines = [String(localized: "\(openTaskCount) görev açık", bundle: bundle, locale: locale)]
        lines += openTasks.map { String(localized: "Açık: \($0)", bundle: bundle, locale: locale) }
        let rest = openTaskCount - openTasks.count
        if rest > 0 { lines.append(String(localized: "ve \(rest) görev daha", bundle: bundle, locale: locale)) }
        return lines
    }

    func peopleLines(locale: Locale) -> [String] {
        guard !people.isEmpty else { return [] }
        let names = people.joined(separator: ", ")
        return [
            String(
                localized: "Görüşmeyeli bir süre oldu: \(names)", bundle: PresentationLocalization.bundle(locale),
                locale: locale)
        ]
    }

    func goalLines(locale: Locale) -> [String] {
        goals.map { Self.line(for: $0, locale: locale) }
    }

    static func line(for goal: WeeklyReviewGoal, locale: Locale) -> String {
        "\(goal.name): \(standingText(goal.standing, locale: locale))"
    }

    static func standingText(_ standing: WeeklyReviewGoal.Standing, locale: Locale) -> String {
        switch standing {
        case .days(let met, let count):
            return String(
                localized: "\(met)/\(count) gün", bundle: PresentationLocalization.bundle(locale), locale: locale)
        case .amount(let done, let target, let unit):
            let number = FloatingPointFormatStyle<Double>.number.locale(locale)
            return "\(done.formatted(number)) / \(target.formatted(number))" + (unit.map { " " + $0 } ?? "")
        }
    }
}

/// How a finished review ended; shown where the sheet was opened from.
enum WeeklyReviewResult: Equatable, Sendable {
    case written
    /// The file holds the text; only the index did not follow. The write is not repeated.
    case writtenWithoutIndex
}

/// State of the review. Nothing is written until "Günlüğe yaz"; leaving before that touches no
/// file. The text written is the text previewed: both come from ``previewLines``.
@MainActor @Observable
final class WeeklyReviewModel {
    let store: IndexStore
    /// The day the review is made on: the week is counted from it and its Journal gets the text.
    let today: CalendarDate
    private let calendar: Calendar
    private let locale: Locale
    private let defaults: UserDefaults
    /// The vault the review was opened on; its numbers are never written into another one.
    private let root: URL?
    /// The store's Journal append; tests replace it to fail the way a real write can.
    private let append: @MainActor (CalendarDate, [String]) async throws -> Void

    private(set) var step: WeeklyReviewStep
    var week = WeeklyReviewWeek.current {
        didSet { if week != oldValue { recompute() } }
    }
    var note = ""
    private(set) var content: WeeklyReviewContent?
    private(set) var isLoading = false
    private(set) var loadErrorText: String?
    private(set) var isWriting = false
    private(set) var errorText: String?
    private(set) var result: WeeklyReviewResult?
    private var included = Set(WeeklyReviewSection.allCases)
    private var input: SummaryInput?
    private var cadences: [String: PersonCadence] = [:]
    private var lastEncounters: [String: CalendarDate] = [:]
    /// Open tasks left from either week (``IndexStore/computeOpenTasks(dueBy:orWrittenFrom:)``).
    private var openTasks: [TaskRow] = []

    init(
        store: IndexStore, today: CalendarDate, calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent, defaults: UserDefaults = .standard,
        step: WeeklyReviewStep = .numbers,
        append: (@MainActor (CalendarDate, [String]) async throws -> Void)? = nil
    ) {
        self.store = store
        self.today = today
        self.calendar = calendar
        self.locale = PresentationLocalization.resolvedLocale(locale)
        self.defaults = defaults
        self.step = step
        root = store.vaultURL
        self.append = append ?? { try await store.appendToJournal(on: $0, lines: $1) }
    }

    var range: ClosedRange<CalendarDate> { week.range(containing: today, calendar: calendar) }

    func advance() { if let next = step.next { step = next } }
    func back() { if let previous = step.previous { step = previous } }

    func isIncluded(_ section: WeeklyReviewSection) -> Bool { included.contains(section) }

    func setIncluded(_ section: WeeklyReviewSection, _ isOn: Bool) {
        guard !isWriting else { return }
        if isOn { included.insert(section) } else { included.remove(section) }
    }

    /// The sentences a section offers, whether or not it is included.
    func lines(for section: WeeklyReviewSection) -> [String] {
        guard let content else { return [] }
        switch section {
        case .numbers: return content.numberLines(locale: locale)
        case .tasks: return content.taskLines(locale: locale)
        case .people: return content.peopleLines(locale: locale)
        case .goals: return content.goalLines(locale: locale)
        }
    }

    /// True when passing the step now leaves nothing of it in the output.
    func isSkipped(_ step: WeeklyReviewStep) -> Bool {
        switch step {
        case .numbers: contribution(.numbers).isEmpty
        case .tasks: contribution(.tasks).isEmpty
        case .people: contribution(.people).isEmpty
        case .goals: contribution(.goals).isEmpty
        case .note: note.allSatisfy(\.isWhitespace)
        case .preview: false
        }
    }

    private func contribution(_ section: WeeklyReviewSection) -> [String] {
        isIncluded(section) ? lines(for: section) : []
    }

    /// Exactly the lines "Günlüğe yaz" hands to the store, in the order they are written.
    var previewLines: [String] {
        WeeklyReviewText.lines(
            title: String(
                localized: "Haftalık inceleme", bundle: PresentationLocalization.bundle(locale), locale: locale),
            summaryLines: contribution(.numbers),
            selectedLines: contribution(.tasks) + contribution(.people) + contribution(.goals),
            note: note)
    }

    /// Set when the vault cannot be written at all; the preview says so before anything is tried.
    var blockedText: String? {
        store.isVaultReadOnly ? Self.message(for: VaultStoreError.readOnlyVault, locale: locale) : nil
    }

    var canWrite: Bool {
        !isWriting && result == nil && store.canAddEvent && store.vaultURL == root && !previewLines.isEmpty
    }

    /// While the text is being written the sheet stays: one pass through the flow writes once.
    var canClose: Bool { !isWriting }

    /// Reads both weeks at once, so changing the week needs no second read.
    func load() async {
        guard store.vaultURL == root else { return }
        let first = WeeklyReviewWeek.previous.range(containing: today, calendar: calendar).lowerBound
        let last = WeeklyReviewWeek.current.range(containing: today, calendar: calendar).upperBound
        isLoading = true
        defer { isLoading = false }
        do {
            let read = try await store.weeklyReviewInput(from: first, to: last)
            let fields = try await store.personCadences()
            let encounters = try await store.computeLastEncounters(asOf: today)
            let open = try await store.computeOpenTasks(dueBy: last, orWrittenFrom: first)
            guard store.vaultURL == root else { return }
            input = read
            openTasks = open
            cadences = fields
            lastEncounters = encounters
            loadErrorText = nil
            recompute()
        } catch is CancellationError {
            // A newer publish asked again (`.task(id:)`); its answer is the one to show.
        } catch {
            guard store.vaultURL == root else { return }
            loadErrorText = DayEditError.message(for: error)
        }
    }

    private func recompute() {
        guard let input else { return }
        let unseen = UnseenPeople.compute(
            people: store.content.entities, lastEncounters: lastEncounters, today: today,
            threshold: PeopleInsightsPreference.threshold(in: defaults), cadences: cadences)
        content = WeeklyReviewContent.compute(
            range: range, today: today, input: input, tasks: openTasks, unseen: unseen.overdue)
    }

    /// Appends the previewed lines to the review day's Journal. A second call while the first is
    /// writing, or after it has written, does nothing.
    func write() async {
        guard canWrite else { return }
        let lines = previewLines
        let reviewed = range.lowerBound
        isWriting = true
        defer { isWriting = false }
        errorText = nil
        do {
            try await append(today, lines)
            result = .written
        } catch VaultStoreError.indexUpdateFailed {
            // The bytes are in the file: asking again would write the block twice.
            result = .writtenWithoutIndex
        } catch {
            errorText = Self.message(for: error, locale: locale)
            return
        }
        WeeklyReviewPreference.markReviewed(weekStarting: reviewed, in: defaults)
    }

    static func message(for error: any Error, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        switch error {
        case EditError.sectionNotWritable, EditError.contentNotRepresentable:
            return String(
                localized:
                    "Bugünün dosyasındaki günlük bölümüne eklenemiyor. Kapanmamış kod bloğunu ya da dosyanın başındaki alanları kontrol et.",
                bundle: bundle, locale: locale)
        case EditError.readOnlyDocument:
            return String(
                localized: "Bugünün dosyası okunamadığı için yazılmadı. Dosyanın kodlamasını kontrol et.",
                bundle: bundle, locale: locale)
        case VaultStoreError.readOnlyVault:
            return String(
                localized: "Kasa salt okunur; inceleme günlüğe yazılamaz.", bundle: bundle, locale: locale)
        default:
            return DayEditError.message(for: error)
        }
    }
}

/// What the entry screen says once the sheet has closed on a finished review.
struct WeeklyReviewNotice: Equatable, Sendable {
    let kind: InfoBandKind
    let text: String

    init(_ result: WeeklyReviewResult, locale: Locale) {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let bundle = PresentationLocalization.bundle(resolved)
        switch result {
        case .written:
            kind = .info
            text = String(localized: "Haftalık inceleme günlüğe yazıldı.", bundle: bundle, locale: resolved)
        case .writtenWithoutIndex:
            kind = .warning
            text = String(
                localized: "Haftalık inceleme günlüğe yazıldı, indeks güncellenemedi.", bundle: bundle,
                locale: resolved)
        }
    }
}
