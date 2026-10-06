import SwiftUI
import VaultFormat

struct DayCalendarView: View {
    let date: CalendarDate
    @Environment(CalendarService.self) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        if calendar.showsSection(on: date) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Takvim"))
                if calendar.authorization.canRequest {
                    Button("Takvim etkinliklerini göstermek için izin ver") {
                        Task { await calendar.requestAccess() }
                    }
                    .buttonStyle(InkTextButtonStyle())
                    .disabled(calendar.isRequesting)
                }
                if let error = calendar.errorText {
                    InfoBand(
                        kind: .warning, verbatim: error,
                        actionTitle: calendar.authorization.canRead ? "Yeniden dene" : nil,
                        action: calendar.authorization.canRead
                            ? { Task { await calendar.load(date) } } : nil)
                }
                ForEach(calendar.events(on: date)) { event in
                    InkCalendarRow(
                        time: timeLabel(for: event),
                        title: event.title.isEmpty
                            ? String(localized: "Başlıksız etkinlik") : event.title
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func timeLabel(for event: CalendarEvent) -> String? {
        if event.isAllDay { return String(localized: "Tüm gün") }
        let start = event.start.formatted(.dateTime.hour().minute().locale(locale))
        if LocalDay.today(at: event.start) != LocalDay.today(at: event.end) {
            let end = event.end.formatted(
                .dateTime.day().month(.abbreviated).hour().minute().locale(locale))
            return "\(start)–\(end)"
        }
        let end = event.end.formatted(.dateTime.hour().minute().locale(locale))
        return "\(start)–\(end)"
    }
}
