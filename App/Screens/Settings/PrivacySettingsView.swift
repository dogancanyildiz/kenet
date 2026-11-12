import SwiftUI

/// Privacy: app lock, link to hide notification content, people insights.
struct PrivacySettingsView: View {
    #if os(iOS)
        @Environment(NotificationService.self) private var notifications: NotificationService?
    #endif

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Gizlilik")
            #endif
            AppLockSettingsView()
            #if os(iOS)
                // Mac uses the adjacent Bildirimler Settings tab instead of a push.
                Section {
                    SectionHeader("Bildirimler")
                        .inkListRow()
                    InkCard(padded: false) {
                        NavigationLink {
                            NotificationContentSettingsView()
                        } label: {
                            InkDisclosureRowLabel("Bildirim içeriği", value: contentValue)
                        }
                        .inkDisclosureRow("Bildirim içeriği", value: contentValue)
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

    #if os(iOS)
        /// The row's value: whether banners show the text, as the page's switch says.
        private var contentValue: Text? {
            guard let notifications else { return nil }
            return notifications.preferences.hideContent ? Text("Gizli") : Text("Gösterilir")
        }
    #endif
}
