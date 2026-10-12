import DateParsing
import Foundation

/// Ordered date languages for quick entry and App Intents. Both languages stay in the list, so
/// "tomorrow" and "yarın" both resolve; the first language wins when one token has two readings.
enum DateParsingLanguages {
    /// The app's chosen language, then the system language list.
    static var appLocale: Locale {
        let identifier = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en"
        return Locale(identifier: identifier)
    }

    /// Turkish comes first only for a Turkish locale. Callers pass the locale so a test does not
    /// follow the process language.
    static func preferred(for locale: Locale) -> [DateParsing.Language] {
        let code = locale.language.languageCode?.identifier ?? locale.identifier
        return code.hasPrefix("tr") ? [.turkish, .english] : [.english, .turkish]
    }
}
