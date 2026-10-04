import Foundation
import Observation

@MainActor @Observable
final class IntentNavigation {
    static let shared = IntentNavigation()
    @ObservationIgnored var onOpenToday: (() -> Void)?
    struct MentionRequest {
        let id = UUID()
        let entity: EntitySummary
        let vault: URL?
    }
    private(set) var mentionRequest: MentionRequest?
    private(set) var todayRequest: UUID?
    func mention(_ entity: EntitySummary, vault: URL?) {
        mentionRequest = MentionRequest(entity: entity, vault: vault)
        navigateToday()
    }
    func takeMention(vault: URL?) -> EntitySummary? {
        defer { mentionRequest = nil }
        guard mentionRequest?.vault == vault else { return nil }
        return mentionRequest?.entity
    }
    func openToday() {
        mentionRequest = nil
        navigateToday()
    }
    private func navigateToday() {
        onOpenToday?()
        todayRequest = UUID()
    }
}
