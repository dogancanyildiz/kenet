import Foundation

/// The app's side of a widget tap (`WidgetLink`): it opens Today and marks a yes/no goal for
/// today through the App Intent path (`IntentActions.markGoal`). A local or selected vault's
/// goals come this way; an iCloud vault's are marked in the widget (`WidgetGoalMarker`). A mark
/// asked while the app is locked waits for the unlock.
///
/// The link's source is not checked: the app registers no URL scheme, so only WidgetKit opens a
/// `kenet-widget` link here (`ReleaseConfigurationTests`). A registered scheme would let any app
/// mark goals; it then needs a source check first.
@MainActor final class WidgetLinkHandler {
    private let actions: IntentActions
    private let navigation: IntentNavigation
    /// The goal a tap asked to mark while the app was locked.
    private(set) var pendingMark: String?

    init(actions: IntentActions, navigation: IntentNavigation) {
        self.actions = actions
        self.navigation = navigation
    }

    /// False for a URL that is not a widget link; it is left to whoever else handles it.
    @discardableResult func open(_ url: URL) async -> Bool {
        guard let link = WidgetLink(url: url) else { return false }
        if link == .write {
            navigation.openTodayForWriting(isLocked: actions.isLocked())
            return true
        }
        navigation.openToday()
        if case .markGoal(let id) = link { await mark(id) }
        return true
    }

    /// Marks the goal a locked tap asked for.
    func unlocked() async {
        guard !actions.isLocked() else { return }
        navigation.unlocked()
        guard let id = pendingMark else { return }
        pendingMark = nil
        await mark(id)
    }

    private func mark(_ id: String) async {
        do {
            _ = try await actions.markGoal(id: id)
        } catch IntentActionError.appLocked {
            pendingMark = id
        } catch {
            // The goal or the vault is gone since the widget drew: Today shows the day as it is.
        }
    }
}
