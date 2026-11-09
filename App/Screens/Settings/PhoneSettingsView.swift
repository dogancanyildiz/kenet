import SwiftUI

/// iPhone Settings hub: vault status card at top and six sections in a card below (Mac uses Settings tabs instead).
struct PhoneSettingsView: View {
    let store: IndexStore

    private var vaultLocationTitle: String {
        switch store.vaultKind {
        case .icloud:
            return String(localized: "iCloud Drive › Kenet")
        case .selected:
            if let name = store.vaultURL?.lastPathComponent, !name.isEmpty {
                return name
            }
            return String(localized: "Seçilen klasör")
        case .local:
            switch DeviceIdiom.current {
            case .phone: return String(localized: "Bu iPhone")
            case .pad: return String(localized: "Bu iPad")
            case .mac: return String(localized: "Bu Mac")
            }
        }
    }

    var body: some View {
        List {
            InkPageTitleRow("Ayarlar")
            if store.syncStatus != .idle {
                SyncStatusIndicator(status: store.syncStatus)
                    .inkListRow()
            }
            NavigationLink(value: SettingsSection.vault) {
                InkCard {
                    HStack(spacing: InkSpacing.row) {
                        RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                            .fill(Color.ink.accentSoft)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: store.vaultKind == .icloud ? "icloud" : "folder")
                                    .font(.ink.section)
                                    .foregroundStyle(Color.ink.accent)
                            }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: vaultLocationTitle)
                                .font(.ink.section)
                                .foregroundStyle(Color.ink.text)
                            HStack(spacing: 6) {
                                Text("\(store.counts.files) dosya")
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                                    .monospacedDigit()
                                Text("·")
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.tertiaryText)
                                    .accessibilityHidden(true)
                                Image(
                                    systemName: store.vaultKind == .icloud
                                        ? "checkmark.icloud" : "folder"
                                )
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .accessibilityHidden(true)
                                Text("indeks güncel")
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.ink.weekday)
                            .foregroundStyle(Color.ink.tertiaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .inkListRow()

            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(SettingsSection.allCases.enumerated()), id: \.element.id) {
                        index, section in
                        if index > 0 {
                            InkCardDivider()
                        }
                        NavigationLink(value: section) {
                            HStack(spacing: InkSpacing.row) {
                                RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
                                    .fill(Color.ink.well)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: section.symbol)
                                            .font(.ink.meta.weight(.semibold))
                                            .foregroundStyle(Color.ink.accent)
                                    }
                                    .accessibilityHidden(true)
                                Text(section.title)
                                    .font(.ink.content)
                                    .foregroundStyle(Color.ink.text)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.ink.weekday)
                                    .foregroundStyle(Color.ink.tertiaryText)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .inkListRow()
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Ayarlar")
        .navigationDestination(for: SettingsSection.self) { section in
            settingsDestination(section)
        }
        .inkPage()
        .background(Color.ink.elevated)
        .inkPageScrollColumn()
        .accessibilityIdentifier("screen.settings")
    }

    @ViewBuilder
    private func settingsDestination(_ section: SettingsSection) -> some View {
        switch section {
        case .quickEntry:
            EntryPointsSettingsView()
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
