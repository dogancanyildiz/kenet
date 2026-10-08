import SwiftUI

/// iPhone Settings hub: five sections as a list (Mac uses Settings tabs instead).
struct PhoneSettingsView: View {
    let store: IndexStore

    var body: some View {
        List {
            InkPageTitleRow("Ayarlar")
            ForEach(SettingsSection.allCases) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.symbol)
                }
                .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Ayarlar")
        .navigationDestination(for: SettingsSection.self) { section in
            settingsDestination(section)
        }
        .inkPage()
        .inkPageScrollColumn()
        .accessibilityIdentifier("screen.settings")
    }

    @ViewBuilder
    private func settingsDestination(_ section: SettingsSection) -> some View {
        switch section {
        case .privacy:
            PrivacySettingsView()
        case .notifications:
            NotificationSettingsView()
        case .calendarAndLocation:
            CalendarAndLocationSettingsView()
        case .vault:
            VaultSettingsView(store: store)
        case .diagnostics:
            DiagnosticsView(store: store)
        }
    }
}
