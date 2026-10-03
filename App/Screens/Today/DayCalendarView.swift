import SwiftUI
import VaultFormat

struct DayCalendarView: View {
    let date: CalendarDate
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        if calendar.showsSection(on: date) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Takvim").font(.headline).accessibilityAddTraits(.isHeader)
                if calendar.authorization.canRequest {
                    Button("Takvim etkinliklerini göstermek için izin ver") {
                        Task { await calendar.requestAccess() }
                    }.disabled(calendar.isRequesting)
                }
                if let error = calendar.errorText {
                    Text(verbatim: error).font(.caption).foregroundStyle(.secondary)
                    if calendar.authorization.canRead {
                        Button("Yeniden dene") { Task { await calendar.load(date) } }
                    }
                }
                ForEach(calendar.events(on: date)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                Color(
                                    .sRGB, red: event.color.red, green: event.color.green,
                                    blue: event.color.blue, opacity: event.color.alpha)
                            )
                            .frame(width: 4, height: 32).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            if event.title.isEmpty { Text("Başlıksız etkinlik") } else { Text(verbatim: event.title) }
                            if event.isAllDay {
                                Text("Tüm gün").font(.caption).padding(.horizontal, 6)
                                    .background(.quaternary, in: Capsule())
                            } else {
                                HStack(spacing: 4) {
                                    Text(event.start, format: .dateTime.hour().minute())
                                    Text(verbatim: "–")
                                    if LocalDay.today(at: event.start) != LocalDay.today(at: event.end) {
                                        Text(event.end, format: .dateTime.day().month(.abbreviated).hour().minute())
                                    } else {
                                        Text(event.end, format: .dateTime.hour().minute())
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
}
