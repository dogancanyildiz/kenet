import SwiftUI

/// Privacy: app lock, link to hide notification content, people insights.
struct PrivacySettingsView: View {
    var body: some View {
        Form {
            InkPageTitleRow("Gizlilik")
            AppLockSettingsView()
            #if os(iOS)
                // Mac uses the adjacent Bildirimler Settings tab instead of a push.
                Section {
                    NavigationLink("Bildirimlerde içeriği gizle") {
                        NotificationSettingsView()
                    }
                }
            #endif
            PeopleInsightsSettingsView()
        }
        .formStyle(.grouped)
        .listRowBackground(Color.ink.paper)
        .inkPageNavigationTitle("Gizlilik")
        .inkPageColumn()
        .inkPage()
    }
}
