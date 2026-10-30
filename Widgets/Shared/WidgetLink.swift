import Foundation

/// The widget's link to the app and the kinds the app reloads. Built in the app and the widget
/// (Foundation only), separate from the snapshot so that new widgets add links without touching
/// the file's format.

/// What a tap on a goal row of the widget does.
enum WidgetTap: Equatable, Sendable {
    /// Open the app with the link.
    case open(WidgetLink)
    /// Mark the goal (App Intent identifier) in the widget's process; the app stays closed.
    case markInWidget(goalID: String)
}

/// Widget kinds the app asks WidgetKit to reload (`Widget.kind` of each widget in the bundle).
enum WidgetKinds {
    static let goalChain = "GoalChainWidget"
    /// Every kind: the app reloads them all after a publish.
    static let all = [goalChain]
}

/// What a tap in the widget asks the app to do. The widget passes it as the URL it opens the app
/// with. Only an iCloud vault's open yes/no goal is marked without the app (``WidgetTap``).
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
