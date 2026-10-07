import SwiftUI

/// Privacy: app lock, link to hide notification content, people insights.
struct PrivacySettingsView: View {
    var body: some View {
        Form {
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
        .listRowBackground(Color.ink.surface)
        .inkPageColumn()
        .inkPage()
    }
}
