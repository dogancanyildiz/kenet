import AppIntents
import Foundation

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Bugünü aç"
    static let openAppWhenRun = true
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        IntentNavigation.shared.openToday()
        return .result(dialog: "Bugün açıldı.")
    }
}
