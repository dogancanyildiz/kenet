import Foundation

/// What the home-screen widget shows, written by the app into the App Group
/// (`widget/today.json`, docs/architecture.md "Widget'lar"). The widget is a separate process with
/// little memory and no access to the app's index: it draws only this file. Built in the app and
/// the widget, so it uses Foundation only.
///
/// Nothing here is the source of truth: the app rewrites the file from the index on every publish
/// and removes it when the vault is unavailable or the app is locked. The widget changes it in one
/// case only: after it marked a goal in an iCloud vault itself (``WidgetGoalMarker``), it shows
/// the mark at once and leaves ``markedAt`` for the app to reconcile.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bumped when a field changes meaning; a widget reading another version shows "open Kenet".
    /// New optional fields keep the format: an older reader ignores them.
    static let currentFormat = 1

    var format: Int
    var writtenAt: Date
    /// SHA-256 of the vault's path, as App Intents identify the vault (`IntentGoal.id`).
    var vaultID: String
    /// Today, then the days after it the app computed ahead (tomorrow): at midnight the widget
    /// moves to the next day's entry without the app running.
    var days: [Day]
    /// Where the vault lives (`VaultLocation.Kind`); nil in a snapshot written before it was kept.
    var vaultKind: VaultKind?
    /// For an iCloud vault, its root inside the iCloud container (`Documents/Kenet`): the widget
    /// finds the vault there without the app. Nil for any other vault.
    var cloudRelativePath: String?
    /// For an iCloud vault, which vault folder on this device the app wrote this for
    /// (``cloudVaultIdentity(at:)``): the widget writes only into the same one. Nil for any other
    /// vault, and while the app cannot tell; the widget then leaves the tap to the app.
    var cloudVaultIdentity: String?
    /// Set by the widget when it marked a goal itself and changed the days to match; the app's
    /// next write rescans the day files before it queries, then leaves it out.
    var markedAt: Date?
    /// Notification privacy preference; an older file defaults to hidden in the accessory view.
    var hideContent: Bool?
    /// The app went to the background with a delayed lock (docs/architecture.md "Widget'lar"):
    /// from this moment on the app counts as locked, so the widget shows "open Kenet" and marks
    /// nothing. The app leaves it out once it is in the foreground and unlocked again.
    var lockedAfter: Date?

    init(
        writtenAt: Date, vaultID: String, days: [Day], vaultKind: VaultKind? = nil,
        cloudRelativePath: String? = nil, cloudVaultIdentity: String? = nil, markedAt: Date? = nil,
        lockedAfter: Date? = nil, hideContent: Bool? = nil
    ) {
        format = Self.currentFormat
        self.writtenAt = writtenAt
        self.vaultID = vaultID
        self.days = days
        self.vaultKind = vaultKind
        self.cloudRelativePath = cloudRelativePath
        self.cloudVaultIdentity = cloudVaultIdentity
        self.markedAt = markedAt
        self.hideContent = hideContent
        self.lockedAfter = lockedAfter
    }

    /// The vault's place, as `VaultLocation.Kind` names it.
    enum VaultKind: String, Codable, Sendable {
        case local, selected, icloud
    }

    /// The widget may write this vault itself: only an iCloud vault, which the widget reaches
    /// through the iCloud container, and only one the app named on this device. A local or
    /// selected folder is the app's alone (its sandbox, its security-scoped bookmark).
    var widgetCanMark: Bool {
        vaultKind == .icloud && cloudRelativePath.map { !$0.isEmpty } == true && cloudVaultIdentity != nil
    }

    /// The vault folder at `root` and its settings file `.app/vault.json`, by their file numbers
    /// on this device: the app and the widget see the same numbers, another vault in the same
    /// place (another account's container, a folder put there in Files) has others. Nil when
    /// either is missing (not downloaded yet).
    static func cloudVaultIdentity(at root: URL) -> String? {
        func number(_ url: URL) -> UInt64? {
            ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? NSNumber)?
                .uint64Value
        }
        guard let folder = number(root), let settings = number(root.appendingPathComponent(".app/vault.json"))
        else { return nil }
        return "\(folder):\(settings)"
    }

    struct Day: Codable, Equatable, Sendable {
        /// Local calendar day, `yyyy-MM-dd`.
        var date: String
        /// Daily goals, open ones first, each group by name (``WidgetSnapshot/ordered(_:)``).
        var goals: [Goal]
        var events: [Event]? = nil
        var openTaskCount: Int? = nil
    }

    struct Event: Codable, Equatable, Sendable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
    }

    struct Goal: Codable, Equatable, Sendable, Identifiable {
        var key: String
        var name: String
        var kind: Kind
        var target: Double
        var unit: String?
        /// The day's amount: 1 for a marked yes/no goal, the logged number otherwise.
        var value: Double
        /// The day has not reached the target yet.
        var isPending: Bool
        /// Current chain; for an open day it counts through the day before.
        var streak: Int
        /// Chain days available (decision 67), 0...3.
        var chainDays: Int

        var id: String { key }

        /// Progress of the day, 0...1.
        var fraction: Double { target > 0 ? min(1, max(0, value / target)) : (isPending ? 0 : 1) }
    }

    enum Kind: String, Codable, Sendable {
        case boolean, number
    }

    /// Open goals first, then done ones; each group by name, as the Today strip orders a day.
    static func ordered(_ goals: [Goal]) -> [Goal] {
        goals.sorted {
            if $0.isPending != $1.isPending { return $0.isPending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Same goals, days, vault place and lock moment as `other`; the time of writing and the
    /// widget's mark do not count.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        format == other.format && vaultID == other.vaultID && days == other.days && vaultKind == other.vaultKind
            && cloudRelativePath == other.cloudRelativePath && cloudVaultIdentity == other.cloudVaultIdentity
            && lockedAfter == other.lockedAfter && hideContent == other.hideContent
    }

    /// The App Intent identifier of the goal `key` in the vault `vaultID` (`IntentGoal.id`).
    static func intentID(vaultID: String, key: String) -> String { vaultID + ":" + key }

    /// What a tap on `goal` asks the app for: an open yes/no goal is marked; a done goal and a
    /// number goal (its amount is entered in the app) open Today.
    static func link(for goal: Goal, vaultID: String) -> WidgetLink {
        guard goal.isPending, goal.kind == .boolean else { return .today }
        return .markGoal(id: intentID(vaultID: vaultID, key: goal.key))
    }

    /// What a tap on `goal` does in the widget: an open yes/no goal of an iCloud vault is marked
    /// in the widget's own process (``WidgetGoalMarker``); everything else opens the app with
    /// ``link(for:vaultID:)``.
    func tap(for goal: Goal) -> WidgetTap {
        let link = Self.link(for: goal, vaultID: vaultID)
        guard widgetCanMark, case .markGoal(let id) = link else { return .open(link) }
        return .markInWidget(goalID: id)
    }

    /// The snapshot after the widget marked the yes/no goal `key` on `day`: the goal is done,
    /// its chain one longer, the day's goals reordered (open first). A chain reaching a multiple
    /// of 7 earns a chain day, at most 3 (decision 67, `GoalProgress`). The days after it count
    /// their chain through `day`, so their open entry takes the new chain. The app's next write
    /// replaces all of it with the index's answer: a chain day spent on yesterday's miss shows
    /// only then. Nil when `day` has no such open goal.
    func marking(key: String, on day: String, at time: Date) -> WidgetSnapshot? {
        guard let dayIndex = days.firstIndex(where: { $0.date == day }),
            let goalIndex = days[dayIndex].goals.firstIndex(where: { $0.key == key }),
            days[dayIndex].goals[goalIndex].kind == .boolean, days[dayIndex].goals[goalIndex].isPending
        else { return nil }
        var result = self
        var goal = days[dayIndex].goals[goalIndex]
        goal.isPending = false
        goal.value = goal.target
        goal.streak += 1
        if goal.streak.isMultiple(of: 7) { goal.chainDays = min(3, goal.chainDays + 1) }
        var goals = days[dayIndex].goals
        goals[goalIndex] = goal
        result.days[dayIndex].goals = Self.ordered(goals)
        for later in result.days.indices where result.days[later].date > day {
            guard let index = result.days[later].goals.firstIndex(where: { $0.key == key }) else { continue }
            result.days[later].goals[index].streak = goal.streak
            result.days[later].goals[index].chainDays = goal.chainDays
        }
        result.markedAt = time
        return result
    }

    /// What the widget shows from `now` on: one entry per stored day from today, each from the
    /// start of its day (the first from `now`), then "open Kenet" from the end of the last day,
    /// or from ``lockedAfter`` if that comes first. A snapshot of another format, with no day
    /// left, or with the lock moment past, gives "open Kenet" from `now`.
    func timeline(from now: Date, calendar: Calendar) -> [WidgetTimelineEntry] {
        let days = dayTimeline(from: now, calendar: calendar)
        guard let lockedAfter, lockedAfter < days.last?.date ?? now else { return days }
        guard lockedAfter > now else { return [WidgetTimelineEntry(date: now, day: nil)] }
        return days.filter { $0.date < lockedAfter } + [WidgetTimelineEntry(date: lockedAfter, day: nil)]
    }

    /// Day transitions plus event ends; the view selects the first event still in progress.
    func lockScreenTimeline(from now: Date, calendar: Calendar) -> [WidgetTimelineEntry] {
        let base = timeline(from: now, calendar: calendar)
        var entries = base
        if base.first?.date != now { entries.append(.init(date: now, day: nil)) }
        for entry in base {
            guard let day = entry.day,
                let start = WidgetDay.start(of: day.date, calendar: calendar),
                let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { continue }
            for event in day.events ?? [] where event.end > entry.date && event.end < end {
                guard !isLocked(at: event.end) else { continue }
                entries.append(.init(date: event.end, day: day))
            }
        }
        var seen: Set<Date> = []
        return entries.sorted { $0.date < $1.date }.filter { seen.insert($0.date).inserted }
    }

    /// Whether the app counts as locked at `time` (``lockedAfter``): the widget then marks nothing.
    func isLocked(at time: Date) -> Bool {
        lockedAfter.map { time >= $0 } ?? false
    }

    private func dayTimeline(from now: Date, calendar: Calendar) -> [WidgetTimelineEntry] {
        guard format == Self.currentFormat else { return [WidgetTimelineEntry(date: now, day: nil)] }
        let today = WidgetDay.string(for: now, calendar: calendar)
        var entries: [WidgetTimelineEntry] = []
        var lastStart: Date?
        for day in days where day.date >= today {
            guard let start = WidgetDay.start(of: day.date, calendar: calendar) else { continue }
            entries.append(WidgetTimelineEntry(date: max(now, start), day: day))
            lastStart = start
        }
        guard let lastStart, let end = calendar.date(byAdding: .day, value: 1, to: lastStart) else {
            return [WidgetTimelineEntry(date: now, day: nil)]
        }
        entries.append(WidgetTimelineEntry(date: end, day: nil))
        return entries
    }
}

/// One step of the widget's timeline: a day's goals, or nil for "open Kenet".
struct WidgetTimelineEntry: Equatable, Sendable {
    let date: Date
    let day: WidgetSnapshot.Day?
}

/// `yyyy-MM-dd` days, as the app writes them (`LocalDay`: Gregorian, the device's time zone).
enum WidgetDay {
    /// The calendar the app's days are in, whatever calendar the device shows.
    static var deviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static func string(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func start(of day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

/// The snapshot file in the App Group container.
enum WidgetSnapshotFile {
    static let relativePath = "widget/today.json"

    static func url(in container: URL) -> URL {
        container.appendingPathComponent(relativePath, isDirectory: false)
    }

    /// Nil when there is no file or it does not decode: the widget then shows "open Kenet".
    static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Writes to a temporary file and moves it into place: the widget never reads half a file.
    static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
