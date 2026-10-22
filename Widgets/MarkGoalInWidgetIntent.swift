import AppIntents
import Foundation
import WidgetKit

/// A tap on an open yes/no goal of an iCloud vault in the medium widget (``WidgetTap``). It runs
/// in the widget's process and never opens the app: ``WidgetGoalMarker`` writes the day file and
/// the snapshot, then the widget reloads. Hidden from Shortcuts; the app's `MarkGoalIntent` is the
/// one people use there.
struct MarkGoalInWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Hedefi işaretle"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    /// A locked device (StandBy, the iPad lock screen) asks for the unlock first: the widget's
    /// content is hidden there too (`privacySensitive`).
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// The goal's App Intent identifier (`IntentGoal.id`: vault, then key).
    @Parameter(title: "Hedef") var goalID: String

    init() {}

    init(goalID: String) {
        self.goalID = goalID
    }

    func perform() async throws -> some IntentResult {
        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)
        if let group {
            let marker = WidgetGoalMarker(
                groupContainer: group, ubiquityContainer: { await Self.ubiquityContainer() }, now: { Date() })
            _ = await marker.mark(goalID: goalID)
        }
        // A failed mark changed nothing; the reload still redraws from the current snapshot.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.goalChain)
        return .result()
    }

    /// The iCloud container, as the app finds it (`SystemUbiquityContainer`): nil without an
    /// iCloud account. Both calls may block, so they run off the caller's thread.
    private static func ubiquityContainer() async -> URL? {
        await Task.detached {
            guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
            return FileManager.default.url(forUbiquityContainerIdentifier: AppIdentifiers.iCloudContainer)
        }.value
    }
}
