import Foundation
import VaultFormat

enum NotificationDestination: String, Codable, Sendable {
    case tasks, goals, diary, people
    var prefix: String { self == .tasks ? "task" : rawValue }
    /// Also reads the diary reminder's identifier of a build before 2026-11-13, so a reminder
    /// still pending or delivered from it opens the diary and the next plan removes it.
    static func from(identifier: String) -> Self? {
        let prefixes =
            [Self.tasks, .goals, .diary, .people].map { ($0, $0.prefix) }
            + [(Self.diary, LegacyDefaults.codeName)]
        for (destination, prefix) in prefixes {
            let prefix = prefix + "-"
            if identifier.hasPrefix(prefix), CalendarDate(String(identifier.dropFirst(prefix.count))) != nil {
                return destination
            }
        }
        return nil
    }
}

/// Screen a tapped notification opens. Goals and the diary prompt both land on Today.
enum NotificationRoute: Equatable, Sendable {
    case today
    case tasks
    case unseenPeople

    init(_ destination: NotificationDestination) {
        switch destination {
        case .tasks: self = .tasks
        case .goals, .diary: self = .today
        case .people: self = .unseenPeople
        }
    }
}

/// Notification text the system resolves when it delivers, not when the app plans: a catalog key
/// with its arguments, or the user's own words. A reminder planned up to six days ahead then
/// follows a language change made before it fires, without the app opening in between.
///
/// The key's format takes only `%@`: the delivery-time formatter (`UNLocalizedString`) fills
/// neither `%lld` nor a plural variation. A count is passed as its digits, and a text whose
/// singular differs has its own key.
struct NotificationText: Equatable, Sendable {
    /// Key in the main bundle's `Localizable` table; nil for verbatim text held in `arguments`.
    let key: String?
    let arguments: [String]

    static func verbatim(_ text: String) -> Self { Self(key: nil, arguments: [text]) }
    static func localized(_ key: String, _ arguments: String...) -> Self { Self(key: key, arguments: arguments) }

    /// The text in the process language, for the app's own screens. A notification takes
    /// `SystemNotificationScheduler`'s delivery-time string instead.
    var resolved: String { resolved(in: .main) }

    func resolved(in bundle: Bundle) -> String {
        guard let key else { return arguments.first ?? "" }
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        // A format asking for more than the arguments hold, or for anything but `%@`, is returned
        // as written: `String(format:)` would read past the arguments.
        guard let needed = Self.argumentCount(of: format), needed <= arguments.count else { return format }
        return String(format: format, arguments: arguments)
    }

    /// Arguments a format reads: its `%@` count or its highest `%n$@`, whichever is larger. `%%`
    /// reads none. Nil when the format holds any other specifier.
    static func argumentCount(of format: String) -> Int? {
        var sequential = 0
        var highest = 0
        for match in format.matches(of: /%(?:(\d+)\$)?(.)/) {
            switch (match.output.1, match.output.2) {
            case (nil, "%"): continue
            case (nil, "@"): sequential += 1
            case (let position?, "@"):
                guard let position = Int(position), position > 0 else { return nil }
                highest = max(highest, position)
            default: return nil
            }
        }
        return format.hasSuffix("%") && !format.hasSuffix("%%") ? nil : max(sequential, highest)
    }

    /// Form kept in a pending request's `userInfo`, so a pending copy compares to the planned one
    /// by key and arguments in any language.
    var stored: [String] { [key ?? ""] + arguments }

    init(key: String?, arguments: [String]) {
        self.key = key
        self.arguments = arguments
    }

    init?(stored: [String]) {
        guard let first = stored.first else { return nil }
        if first.isEmpty {
            guard stored.count == 2 else { return nil }
            self = .verbatim(stored[1])
        } else {
            self.init(key: first, arguments: Array(stored.dropFirst()))
        }
    }
}

struct NotificationRequest: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let titleText: NotificationText
    let bodyText: NotificationText
    let destination: NotificationDestination

    /// Title and body in the process language, as the settings list shows them.
    var title: String { titleText.resolved }
    var body: String { bodyText.resolved }

    init(id: String, date: Date, title: NotificationText, body: NotificationText, destination: NotificationDestination)
    {
        self.id = id
        self.date = date
        titleText = title
        bodyText = body
        self.destination = destination
    }

    /// Verbatim text: a request read back without its stored form, as one from a build before
    /// 2026-11-13.
    init(id: String, date: Date, title: String, body: String, destination: NotificationDestination) {
        self.init(id: id, date: date, title: .verbatim(title), body: .verbatim(body), destination: destination)
    }
}

extension NotificationRequest {
    /// Same identifier, text (key and arguments) and destination, firing within the same second. The system keeps the
    /// trigger's date only to the second, so a pending copy compares to the planned one this way.
    func isSameSchedule(as other: NotificationRequest) -> Bool {
        id == other.id && titleText == other.titleText && bodyText == other.bodyText
            && destination == other.destination
            && Int(date.timeIntervalSince1970.rounded(.down)) == Int(other.date.timeIntervalSince1970.rounded(.down))
    }
}

struct NotificationNavigationRequest: Identifiable, Sendable {
    let id = UUID()
    let destination: NotificationDestination
}

enum NotificationAuthorization: CaseIterable, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown
    var canSchedule: Bool { self == .authorized || self == .provisional || self == .ephemeral }
    var canRequest: Bool { self == .notDetermined }
}

@MainActor
protocol NotificationScheduling {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [NotificationRequest]
    func add(_ request: NotificationRequest) async throws
    func remove(identifiers: [String]) async
    func removeAllDeliveredNotifications() async
    func activate(response: @escaping @MainActor @Sendable (NotificationDestination) -> Void)
}
