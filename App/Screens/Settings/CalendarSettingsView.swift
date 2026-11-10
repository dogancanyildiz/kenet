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
                    InkCardDivider()
                    Button("Sistem ayarlarını aç") { openSystemSettings() }
                        .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                        .padding(.horizontal, InkSpacing.cardPadding)
                }
            }
            .inkListRow()
            Text(
                "Takvim etkinlikleri yalnızca okunur; takvimine yazılmaz. Bir etkinlikten düşürdüğün olay taslağı, sen gönderince günlüğüne yazılır."
            )
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
