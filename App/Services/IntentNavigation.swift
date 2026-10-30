import AppIntents
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
    private(set) var focusRequest: UUID?
    private(set) var pendingFocus = false

    func openTodayForWriting(isLocked: Bool = IntentActions.shared.isLocked()) {
        if isLocked {
            pendingFocus = true
            return
        }
        pendingFocus = false
        mentionRequest = nil
        focusRequest = UUID()
        navigateToday()
    }

    func unlocked() {
        if pendingFocus { openTodayForWriting(isLocked: false) }
    }
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

/// App target implementation; the widget target supplies a no-op implementation.
extension OpenQuickEntryIntent {
    @MainActor
    func perform() async throws -> some IntentResult {
        IntentNavigation.shared.openTodayForWriting()
        return .result()
    }
}
