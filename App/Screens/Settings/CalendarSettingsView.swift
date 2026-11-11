import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct CalendarSettingsView: View {
    @Environment(CalendarService.self) private var calendar
    @Environment(\.openURL) private var openURL
    @State private var calendars: [CalendarTarget] = []

    var body: some View {
        Section {
            SectionHeader("Takvim")
                .task(id: calendar.changeCount) { calendars = await calendar.writableCalendars() }
                .inkListRow()
            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch calendar.authorization {
                    case .notDetermined, .writeOnly:
                        Button("Takvim etkinliklerini göstermek için izin ver") {
                            Task { await calendar.requestAccess() }
                        }
                        .disabled(calendar.isRequesting)
                        .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                        .padding(.horizontal, InkSpacing.cardPadding)
                    case .fullAccess:
                        Text("Takvim erişimine izin verildi.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.text)
                            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                    case .denied:
                        Text(
                            "Takvim erişimi reddedildi. Etkinlikleri göstermek için sistem ayarlarından izin verebilirsin."
                        )
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                        .padding(.horizontal, InkSpacing.cardPadding)
                        .padding(.vertical, 8)
                    case .restricted:
                        Text("Takvim erişimi bu cihazda kısıtlanmış.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                    }
                    if calendar.authorization.canRead, !calendars.isEmpty {
                        InkCardDivider()
                        InkLabeledMenu(
                            "Varsayılan takvim", selection: defaultBinding,
                            sections: [
                                [InkMenuOption("Sistem varsayılanı", value: "")],
                                calendars.map { InkMenuOption(verbatim: $0.title, value: $0.id) },
                            ],
                            identifier: "menu.settings.defaultCalendar"
                        )
                        .padding(.horizontal, InkSpacing.cardPadding)
                    }
                    InkCardDivider()
                    Button("Sistem ayarlarını aç") { openSystemSettings() }
                        .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                        .padding(.horizontal, InkSpacing.cardPadding)
                }
            }
            .inkListRow()
            Text(
                "Uygulama takvim etkinliklerini okur. Takvime yalnız senin eklediğin, düzenlediğin ya da sildiğin etkinliği yazar; görevler ve olaylar takvime yazılmaz."
            )
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .inkListRow()
            Text("Bir etkinlikten düşürdüğün olay taslağı, sen gönderince günlüğüne yazılır.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
            if let error = calendar.errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
        }
    }

    private var defaultBinding: Binding<String> {
        Binding(
            get: {
                guard let id = calendar.defaultCalendarID, calendars.contains(where: { $0.id == id }) else { return "" }
                return id
            },
            set: { calendar.defaultCalendarID = $0.isEmpty ? nil : $0 })
    }

    private func openSystemSettings() {
        #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #elseif os(macOS)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                openURL(url)
            }
        #endif
    }
}
