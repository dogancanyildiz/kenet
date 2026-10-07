import AppIntents
import Foundation
import VaultFormat

struct AddEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Günlüğe olay ekle"
    static let openAppWhenRun = false
    @Parameter(title: "Metin") var text: String
    @Parameter(title: "Saat", kind: .time) var time: Date?
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await IntentActions.shared.addEvent(text: text, time: time.map { LocalDay.clock(at: $0) })
        return .result(value: result.text, dialog: IntentDialog(result.dialog))
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Görev ekle"
    static let openAppWhenRun = false
    @Parameter(title: "Metin") var text: String
    @Parameter(title: "Tarih", kind: .date) var date: Date?
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await IntentActions.shared.addTask(
            text: text, due: date.map { LocalDay.today(at: $0) },
            confirmAssumedDate: { assumed in
                let formatted = LocalDay.instant(for: assumed).formatted(.dateTime.day().month(.wide))
                do {
                    try await requestConfirmation(dialog: IntentDialog("\(formatted) olarak mı?"))
                    return true
                } catch {
                    return false
                }
            })
        return .result(value: result.text, dialog: IntentDialog(result.dialog))
    }
}
