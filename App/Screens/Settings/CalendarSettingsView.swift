import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct CalendarSettingsView: View {
    @Environment(CalendarService.self) private var calendar
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            SectionHeader("Takvim")
                .inkListRow()
            Text("Takvim etkinlikleri yalnızca gösterilir; takvimine ve günlük dosyalarına yazılmaz.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
            switch calendar.authorization {
            case .notDetermined, .writeOnly:
                Button("Takvim etkinliklerini göstermek için izin ver") {
                    Task { await calendar.requestAccess() }
                }
                .disabled(calendar.isRequesting)
                .inkListRow()
            case .fullAccess:
                Text("Takvim erişimine izin verildi.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.text)
                    .inkListRow()
            case .denied:
                Text("Takvim erişimi reddedildi. Etkinlikleri göstermek için sistem ayarlarından izin verebilirsin.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            case .restricted:
                Text("Takvim erişimi bu cihazda kısıtlanmış.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
            Button("Sistem ayarlarını aç") { openSystemSettings() }
                .inkListRow()
            if let error = calendar.errorText {
                Text(verbatim: error)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
        }
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
