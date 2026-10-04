import SwiftUI
import VaultFormat

extension TaskRecurrence {
    static func weekdayTitle(_ day: Int) -> LocalizedStringKey {
        switch day {
        case 0: "Pazartesi"
        case 1: "Salı"
        case 2: "Çarşamba"
        case 3: "Perşembe"
        case 4: "Cuma"
        case 5: "Cumartesi"
        default: "Pazar"
        }
    }
}

struct TaskRecurrenceLabel: View {
    let recurrence: TaskRecurrence
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "repeat")
            switch recurrence.frequency {
            case .weekday(let day): Text(TaskRecurrence.weekdayTitle(day))
            case .interval(let count, let unit):
                switch unit {
                case .day: Text("Her \(count) gün")
                case .week: Text("Her \(count) hafta")
                case .month: Text("Her \(count) ay")
                case .year: Text("Her \(count) yıl")
                }
            }
            if recurrence.whenDone { Text("Tamamlanınca") }
        }
    }
}
