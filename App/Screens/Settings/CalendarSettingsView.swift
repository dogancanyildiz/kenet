import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct CalendarSettingsView: View {
    @Environment(CalendarService.self) private var calendar
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Takvim") {
            Text("Takvim etkinlikleri yalnızca gösterilir; takvimine ve günlük dosyalarına yazılmaz.")
                .font(.caption).foregroundStyle(.secondary)
            switch calendar.authorization {
            case .notDetermined, .writeOnly:
                Button("Takvim etkinliklerini göstermek için izin ver") {
                    Task { await calendar.requestAccess() }
                }.disabled(calendar.isRequesting)
            case .fullAccess:
                Text("Takvim erişimine izin verildi.")
            case .denied:
                Text("Takvim erişimi reddedildi. Etkinlikleri göstermek için sistem ayarlarından izin verebilirsin.")
            case .restricted:
                Text("Takvim erişimi bu cihazda kısıtlanmış.")
            }
            Button("Sistem ayarlarını aç") { openSystemSettings() }
            if let error = calendar.errorText { Text(verbatim: error).font(.caption).foregroundStyle(.secondary) }
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
