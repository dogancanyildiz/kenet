import SwiftUI

/// Privacy: app lock, link to hide notification content, people insights.
struct PrivacySettingsView: View {
    var body: some View {
        Form {
            AppLockSettingsView()
            Section {
                NavigationLink("Bildirimlerde içeriği gizle") {
                    NotificationSettingsView()
                }
                Text("Afiş, bildirim merkezi ve kilit ekranında görev metni ve hedef adları gösterilmez.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            PeopleInsightsSettingsView()
        }
        .formStyle(.grouped)
        .inkPage()
        .inkPageColumn()
    }
}
