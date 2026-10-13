import SwiftUI
import VaultFormat

/// What the split shell (`MacNavigation`) has selected: the section and the row each list
/// column shows in the detail. One object, so a later owner above the shell can keep it when
/// the iPhone Duo swaps the tab shell for the split shell; today the shell owns its own.
@MainActor @Observable
final class ShellNavigationState {
    var section: DesktopSection? = .today
    /// The detail column's stack.
    var detailPath = NavigationPath()
    var selectedDay: String?
    var selectedTask: String?
    var selectedProject: String?
    var selectedGoal: String?
    var selectedEntity: String?
    var selectedSummary: EntitySummary?
    /// Rebuilds the entity page when the list picks a row (also the same row again).
    var entityRouteID = UUID()
    var selectedEntityKind = "person"
    var entityOrder = EntityOrdering.name
    var entitySearch = ""
    /// A notification asked for the unseen people: the list opens that section once per request.
    var unseenReveal: UUID?
}

/// The phone tabs, in tab bar order.
enum PhoneTab: Hashable, CaseIterable { case today, days, tasks, entities, goals }

extension DesktopSection {
    /// The phone tab that holds this section. The one table between the two shells: a section
    /// without a tab of its own opens from inside one (Özetler from Günlük, Konumlar, Graph and
    /// Harita from Kişiler ve Konumlar).
    var phoneTab: PhoneTab {
        switch self {
        case .today: .today
        case .days, .summaries: .days
        case .tasks: .tasks
        case .people, .places, .graph, .map: .entities
        case .goals: .goals
        }
    }
}

extension PhoneTab {
    /// The section a tab opens in the split shell: the first one, in sidebar order, it holds.
    var desktopSection: DesktopSection {
        DesktopSection.allCases.first { $0.phoneTab == self } ?? .today
    }
}
