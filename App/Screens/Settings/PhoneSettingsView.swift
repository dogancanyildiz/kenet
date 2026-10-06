import SwiftUI

/// iPhone Settings hub: five sections as a list (Mac uses Settings tabs instead).
struct PhoneSettingsView: View {
    let store: IndexStore

    var body: some View {
        List {
            ForEach(SettingsSection.allCases) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.symbol)
                }
            }
        }
        .navigationTitle("Ayarlar")
        .navigationDestination(for: SettingsSection.self) { section in
            settingsDestination(section)
        }
        .inkPage()
        .accessibilityIdentifier("screen.settings")
    }

    @ViewBuilder
    private func settingsDestination(_ section: SettingsSection) -> some View {
        switch section {
        case .privacy:
            PrivacySettingsView()
                .navigationTitle("Gizlilik")
        case .notifications:
            NotificationSettingsView()
        case .calendarAndLocation:
            CalendarAndLocationSettingsView()
                .navigationTitle("Takvim ve Konum")
        case .vault:
            VaultSettingsView(store: store)
                .navigationTitle("Kasa")
        case .diagnostics:
            DiagnosticsView(store: store)
                .navigationTitle("Tanılama")
        }
    }
}
