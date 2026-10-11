import AppIntents
import SwiftUI

/// Device preference for the one-time entry-path hint on the main screen.
enum EntryPointsTipPreference {
    static let key = "entryPoints.tipDismissed"

    static func isDismissed(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    /// Writes the dismissal. The hint stays gone for this device.
    static func dismiss(in defaults: UserDefaults) {
        defaults.set(true, forKey: key)
    }

    /// Hidden once dismissed, and whenever automatic start is off (UI tests, `JOURNAL_NO_AUTOSTART`).
    static func shouldPresent(
        dismissed: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        !dismissed
            && AppLaunchPolicy.allowsAutomaticStart(environment: environment, arguments: arguments)
    }
}

/// Siri phrases registered by `JournalShortcuts`, shown with the app's display name filled in.
enum EntryPointPhrases {
    static let applicationNameToken = "${applicationName}"

    static func applicationName(bundle: Bundle = .main) -> String {
        if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !display.isEmpty {
            return display
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
            return name
        }
        return "Kenet"
    }

    /// Templates in provider order. `AppShortcut` takes its phrases as literals and keeps them
    /// internal, so the page holds its own list; a test checks it against `JournalShortcuts`.
    static let templates = [
        "${applicationName} ile günlüğe olay ekle",
        "${applicationName} ile görev ekle",
        "${applicationName} ile hedefi işaretle",
        "${applicationName} ile bugünü aç",
    ]

    static func displayed(applicationName: String, locale: Locale, bundle: Bundle = .main) -> [String] {
        templates.map { displayed($0, applicationName: applicationName, locale: locale, bundle: bundle) }
    }

    static func displayed(
        _ template: String, applicationName: String, locale: Locale, bundle: Bundle = .main
    ) -> String {
        let localized = String(
            localized: String.LocalizationValue(template),
            table: "AppShortcuts",
            bundle: bundle,
            locale: locale
        )
        return localized.replacingOccurrences(of: applicationNameToken, with: applicationName)
    }
}

/// The Action Button is an iPhone control. Kept off the view type so tests can read it
/// without hopping to the main actor.
enum EntryPointPlatform {
    static var showsActionButton: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }
}

/// iPhone page for the paths that already exist. Mac inserts ``EntryPointSections`` into the
/// shortcut tab instead of pushing this page.
struct EntryPointsSettingsView: View {
    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Hızlı giriş")
            #endif
            EntryPointSections()
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Hızlı giriş")
        .inkPageScrollColumn()
        .inkPage()
        .accessibilityIdentifier("screen.settings.quickEntry")
    }
}

/// Siri phrases and Shortcuts. The Action Button block is iPhone-only.
struct EntryPointSections: View {
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            SectionHeader("Siri cümleleri")
                .inkListRow()
            Text("Bu cümleler Siri'ye söylenir.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
            ForEach(phrases, id: \.self) { phrase in
                Text(verbatim: phrase)
                    .foregroundStyle(Color.ink.text)
                    .textSelection(.enabled)
                    .inkListRow()
            }
        }
        Section {
            SectionHeader("Kısayollar")
                .inkListRow()
            Text("Aynı cümleler Kısayollar uygulamasında da çalışır.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        }
        if EntryPointPlatform.showsActionButton {
            Section {
                SectionHeader("Eylem düğmesi")
                    .inkListRow()
                Text("Ayarlar'da Eylem düğmesine bu kısayollardan birini atayabilirsin.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
        }
    }

    private var phrases: [String] {
        EntryPointPhrases.displayed(
            applicationName: EntryPointPhrases.applicationName(), locale: locale)
    }
}
