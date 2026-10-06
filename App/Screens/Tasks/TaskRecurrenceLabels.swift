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

    /// Interval label; singular/plural forms come from String Catalog variations.
    static func intervalLabel(
        count: Int, unit: TaskRecurrence.Unit, locale: Locale = .current
    ) -> String {
        switch unit {
        case .day: String(localized: "Her \(count) gün", locale: locale)
        case .week: String(localized: "Her \(count) hafta", locale: locale)
        case .month: String(localized: "Her \(count) ay", locale: locale)
        case .year: String(localized: "Her \(count) yıl", locale: locale)
        }
    }
}

struct TaskRecurrenceLabel: View {
    @Environment(\.locale) private var locale
    let recurrence: TaskRecurrence
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "repeat")
            switch recurrence.frequency {
            case .weekday(let day): Text(TaskRecurrence.weekdayTitle(day))
            case .interval(let count, let unit):
                Text(verbatim: TaskRecurrence.intervalLabel(count: count, unit: unit, locale: locale))
            }
            if recurrence.whenDone { Text("Tamamlanınca") }
        }
    }
}
