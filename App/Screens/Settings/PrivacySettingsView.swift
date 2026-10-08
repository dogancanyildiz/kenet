import SwiftUI

/// Privacy: app lock, link to hide notification content, people insights.
struct PrivacySettingsView: View {
    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Gizlilik")
            #endif
            AppLockSettingsView()
            #if os(iOS)
                // Mac uses the adjacent Bildirimler Settings tab instead of a push.
                Section {
                    NavigationLink("Bildirimlerde içeriği gizle") {
                        NotificationSettingsView()
                    }
                    .inkListRow()
                }
            #endif
            PeopleInsightsSettingsView()
        }
        .listStyle(.plain)
        .inkToggle()
        .inkPageNavigationTitle("Gizlilik")
        .inkPageScrollColumn()
        .inkPage()
    }
}
