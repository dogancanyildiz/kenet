import Foundation

/// What the home-screen widget shows, written by the app into the App Group
/// (`widget/today.json`, docs/architecture.md "Widget'lar"). The widget is a separate process with
/// little memory and no access to the vault or its index: it reads only this file. Built in the
/// app and the widget, so it uses Foundation only.
///
/// Nothing here is the source of truth: the app rewrites the file from the index on every publish
/// and removes it when the vault is unavailable or the app is locked.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bumped when a field changes meaning; a widget reading another version shows "open Kenet".
    static let currentFormat = 1

    var format: Int
    var writtenAt: Date
    /// SHA-256 of the vault's path, as App Intents identify the vault (`IntentGoal.id`).
    var vaultID: String
    /// Today, then the days after it the app computed ahead (tomorrow): at midnight the widget
    /// moves to the next day's entry without the app running.
    var days: [Day]

    init(writtenAt: Date, vaultID: String, days: [Day]) {
        format = Self.currentFormat
        self.writtenAt = writtenAt
        self.vaultID = vaultID
        self.days = days
    }

    struct Day: Codable, Equatable, Sendable {
        /// Local calendar day, `yyyy-MM-dd`.
        var date: String
        /// Daily goals, open ones first, each group by name (``WidgetSnapshot/ordered(_:)``).
        var goals: [Goal]
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

    /// Same goals and days as `other`; the time of writing does not count.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        format == other.format && vaultID == other.vaultID && days == other.days
    }

    /// The App Intent identifier of the goal `key` in the vault `vaultID` (`IntentGoal.id`).
    static func intentID(vaultID: String, key: String) -> String { vaultID + ":" + key }

    /// What a tap on `goal` asks the app for: an open yes/no goal is marked; a done goal and a
    /// number goal (its amount is entered in the app) open Today.
    static func link(for goal: Goal, vaultID: String) -> WidgetLink {
        guard goal.isPending, goal.kind == .boolean else { return .today }
        return .markGoal(id: intentID(vaultID: vaultID, key: goal.key))
    }

    /// What the widget shows from `now` on: one entry per stored day from today, each from the
    /// start of its day (the first from `now`), then "open Kenet" from the end of the last day.
    /// A snapshot of another format, or with no day left, gives "open Kenet" from `now`.
    func timeline(from now: Date, calendar: Calendar) -> [WidgetTimelineEntry] {
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

/// Widget kinds the app asks WidgetKit to reload.
enum WidgetKinds {
    static let goalChain = "GoalChainWidget"
}

/// What a tap in the widget asks the app to do. The widget passes it as the URL it opens the app
/// with; the widget writes nothing itself.
enum WidgetLink: Equatable, Sendable {
    /// Open the app on Today.
    case today
    /// Open the app on Today and mark the yes/no goal with this App Intent identifier for today.
    case markGoal(id: String)

    static let scheme = "kenet-widget"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .markGoal(let id):
            components.host = "mark"
            components.queryItems = [URLQueryItem(name: "goal", value: id)]
        }
        return components.url!
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == Self.scheme
        else { return nil }
        switch components.host {
        case "today": self = .today
        case "mark":
            guard let id = components.queryItems?.first(where: { $0.name == "goal" })?.value, !id.isEmpty
            else { return nil }
            self = .markGoal(id: id)
        default: return nil
        }
    }
}
