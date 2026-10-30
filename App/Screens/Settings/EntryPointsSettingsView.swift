import AppIntents
import SwiftUI

#if os(iOS)
    import UIKit
#endif

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
        "${applicationName}'e yaz",
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

/// Device kind for copy and keyboard gates only. Layout never reads it: the shell follows the
/// size classes (decisions 2026-10-13). Tests pass each case in directly.
enum DeviceIdiom: Equatable, Sendable {
    case phone
    case pad
    case mac

    /// The device the process runs on.
    @MainActor static var current: DeviceIdiom {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        #else
            .mac
        #endif
    }
}

/// The Action Button is an iPhone control: iPad and Mac have none. Kept off the view type so
/// tests can read it without hopping to the main actor.
enum EntryPointPlatform {
    static func showsActionButton(_ idiom: DeviceIdiom) -> Bool {
        idiom == .phone
    }

    /// The first-use tip names only the paths the device has.
    static func tip(for idiom: DeviceIdiom) -> LocalizedStringResource {
        switch idiom {
        case .phone: "Siri, Kısayollar ve Eylem düğmesiyle de yazabilirsin."
        case .pad: "Siri ve Kısayollar ile de yazabilirsin."
        case .mac: "Siri, Kısayollar ve klavye kısayoluyla da yazabilirsin."
        }
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
    var idiom: DeviceIdiom = .current

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
        if idiom != .mac {
            Section {
                SectionHeader("settings.entry.widget.title")
                    .inkListRow()
                Text("settings.entry.widget.description")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
            }
            Section {
                SectionHeader(
                    EntryPointPlatform.showsActionButton(idiom)
                        ? "settings.entry.action.title" : "settings.entry.control.title"
                )
                .inkListRow()
                Text(
                    EntryPointPlatform.showsActionButton(idiom)
                        ? "settings.entry.action.description" : "settings.entry.control.description"
                )
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
