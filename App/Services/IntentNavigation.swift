import Foundation
import Observation

@MainActor @Observable
final class IntentNavigation {
    static let shared = IntentNavigation()
    @ObservationIgnored var onOpenToday: (() -> Void)?
    private(set) var todayRequest: UUID?
    func openToday() {
        onOpenToday?()
        todayRequest = UUID()
    }
}
