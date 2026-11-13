import SwiftUI

/// iPhone Settings hub: vault status card at top and six sections in a card below (Mac uses Settings tabs instead).
struct PhoneSettingsView: View {
    let store: IndexStore
    @Environment(AppLockService.self) private var lock: AppLockService?
    @Environment(NotificationService.self) private var notifications: NotificationService?
    @Environment(CalendarService.self) private var calendar: CalendarService?
    @Environment(GeofenceService.self) private var geofences: GeofenceService?
    @Environment(\.timeZone) private var timeZone
    @Environment(\.clockNow) private var clockNow
    /// Calendars the hub row counts ("2 takvim"); read again when the calendar store changes.
    @State private var calendarCount = 0

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

    /// The card's index line, from the same store state as Kasa's progress and error rows.
    private var indexState: VaultCardIndexState {
        VaultCardIndexState(
            vaultInaccessible: store.isVaultInaccessible, hasError: store.errorText != nil,
            isProcessing: store.isProcessing)
    }

    var body: some View {
        List {
            InkPageTitleRow("Ayarlar")
            if store.syncStatus != .idle {
                SyncStatusIndicator(status: store.syncStatus)
                    .inkListRow()
            }
            NavigationLink(value: SettingsSection.vault) {
                VaultHubCard {
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
                                    .foregroundStyle(Color.ink.secondaryText)
                                    .accessibilityHidden(true)
                                Image(systemName: indexState.symbol(isCloudVault: store.vaultKind == .icloud))
                                    .font(.ink.meta)
                                    .foregroundStyle(
                                        indexState.isFailure ? Color.ink.danger : Color.ink.secondaryText
                                    )
                                    .accessibilityHidden(true)
                                Text(indexState.title)
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                            }
                            // One element ("30 dosya, dizin güncel"): inside the list cell the
                            // hidden "·" still surfaced as an element of its own, and the iPad
                            // audit named the 4 pt dot as text that does not grow (run 43250059451).
                            .accessibilityElement(children: .combine)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.ink.weekday)
                            .foregroundStyle(Color.ink.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            // The card draws its own chevron; List would add a second one beside it.
            .navigationLinkIndicatorVisibility(.hidden)
            .inkListRow()

            // One list row per section, the card drawn across the rows (InkCardSegment). Six
            // links in one row's card made List fire the last link (Tanılama) for a tap on any of
            // them: a row takes one tap target, whatever its buttons' style.
            let sections = SettingsSection.allCases
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                let segment = InkCardSegment.position(index, of: sections.count)
                NavigationLink(value: section) {
                    sectionRow(section, segment: segment)
                }
                .buttonStyle(.plain)
                .inkListRow(cardSegment: segment)
            }
        }
        .listStyle(.plain)
        // A section row is its text and the row insets (45 pt), as in the one card it was; the
        // list's own minimum would make the middle rows taller than the first and last.
        .environment(\.defaultMinListRowHeight, InkButtonChrome.minimumHeight - 2 * InkListRowInsets.vertical)
        .inkPageNavigationTitle("Ayarlar")
        .navigationDestination(for: SettingsSection.self) { section in
            settingsDestination(section)
                // Each page answers to its section (SettingsHubUITests opens every row).
                .accessibilityIdentifier("screen.settings.\(section.rawValue)")
        }
        .inkPage()
        .background(Color.ink.elevated)
        .inkPageScrollColumn()
        .accessibilityIdentifier("screen.settings")
        .task(id: calendar?.changeCount) {
            guard let calendar, calendar.authorization.canRead else { return }
            calendarCount = await calendar.writableCalendars().count
        }
    }

    /// The line under a hub row: the page's state where it has one (drawing: "Uygulama kilidi
    /// açık · kişi hatırlatmaları", "Günlük hatırlatması 21:30", "2 takvim · konuma girince
    /// kapalı"); otherwise what the page holds.
    private func summary(_ section: SettingsSection) -> Text {
        switch section {
        case .privacy:
            guard let lock else { return Text(section.summary) }
            return lock.isEnabled
                ? Text("Uygulama kilidi açık · kişi hatırlatmaları")
                : Text("Uygulama kilidi kapalı · kişi hatırlatmaları")
        case .notifications:
            guard let notifications else { return Text(section.summary) }
            let preferences = notifications.preferences
            guard preferences.diaryEnabled else { return Text("Günlük hatırlatması kapalı") }
            let time = preferences.fieldDate(
                \.diaryTime, on: LocalDay.today(at: clockNow(), timeZone: timeZone), timeZone: timeZone)
            return Text("Günlük hatırlatması \(Text(time, format: .dateTime.hour().minute()))")
        case .calendarAndLocation:
            guard let calendar else { return Text(section.summary) }
            let calendars =
                calendar.authorization.canRead ? Text("\(calendarCount) takvim") : Text("Takvim izni yok")
            let geofenceOn = geofences.map { !$0.regions.isEmpty } ?? false
            return geofenceOn
                ? Text("\(calendars) · konuma girince açık") : Text("\(calendars) · konuma girince kapalı")
        case .quickEntry, .vault, .diagnostics, .about:
            return Text(section.summary)
        }
    }

    /// A hub row inside the section card: icon tile, title over summary, "›". The list row's
    /// insets (6 pt above and below) are the gap between rows; the card's closed ends add 6 pt
    /// inside, so every row keeps the spacing it had in one card.
    private func sectionRow(_ section: SettingsSection, segment: InkCardSegment) -> some View {
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
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.ink.text)
                    // On the title text the audit reads: NavigationLink cells
                    // drop identifiers on the link itself (settings a11y / AX3).
                    .accessibilityIdentifier("settings.section.\(section.rawValue)")
                // VoiceOver reads the summary as the hint: in the label,
                // "Eylem düğmesi" / "Action button" repeats the button trait.
                summary(section)
                    .font(.caption)
                    .foregroundStyle(Color.ink.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.top, segment.roundsTop ? InkListRowInsets.vertical : 0)
            .padding(.bottom, segment.roundsBottom ? InkListRowInsets.vertical : 0)
            .accessibilityHint(summary(section))
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.ink.weekday)
                .foregroundStyle(Color.ink.secondaryText)
                .accessibilityHidden(true)
        }
        // With the row's insets the cell is at least 44 pt tall.
        .frame(minHeight: InkButtonChrome.minimumHeight - 2 * InkListRowInsets.vertical)
        .padding(.horizontal, InkSpacing.cardPadding)
        .contentShape(Rectangle())
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
        case .about:
            AboutSettingsView()
        }
    }
}

/// What the Settings vault card says about the index: the folder out of reach first (the vault's
/// fault, not the index's), then the store's error, then a refresh under way, otherwise up to date.
enum VaultCardIndexState: Equatable {
    case current, indexing, failed, vaultUnavailable

    init(vaultInaccessible: Bool = false, hasError: Bool, isProcessing: Bool) {
        if vaultInaccessible {
            self = .vaultUnavailable
        } else if hasError {
            self = .failed
        } else if isProcessing {
            self = .indexing
        } else {
            self = .current
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .current: "indeks güncel"
        case .indexing: "indeksleniyor"
        case .failed: "indeks hatası"
        case .vaultUnavailable: "kasa hatası"
        }
    }

    var isFailure: Bool { self == .failed || self == .vaultUnavailable }

    func symbol(isCloudVault: Bool) -> String {
        switch self {
        case .current: isCloudVault ? "checkmark.icloud" : "checkmark.circle"
        case .indexing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        case .vaultUnavailable: "folder.badge.questionmark"
        }
    }
}

/// The hub's vault card: the section card's padding, edge and corner on a surface washed with the
/// accent from the leading top corner (Şafak çizimi: the card sits in the page's glow).
private struct VaultHubCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ScaledMetric(relativeTo: .body) private var padding = InkSpacing.cardPadding
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                shape.fill(Color.ink.surface)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [Color.ink.accentSoft, Color.ink.accentSoft.opacity(0)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay {
                shape.stroke(Color.ink.rule, lineWidth: InkStroke.hairline(scale: displayScale))
            }
    }
}
