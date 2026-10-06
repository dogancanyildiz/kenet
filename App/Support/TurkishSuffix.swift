import Foundation

/// Builds Turkish case suffixes with vowel harmony and consonant voicing.
/// English locales receive the bare name; only Turkish attaches an apostrophe + ending.
enum TurkishSuffix {
    private static let frontVowels: Set<Character> = ["e", "i", "ö", "ü", "E", "İ", "Ö", "Ü"]
    private static let backVowels: Set<Character> = ["a", "ı", "o", "u", "A", "I", "O", "U", "Â", "â"]
    private static let voiceless: Set<Character> = [
        "p", "ç", "t", "k", "f", "h", "s", "ş",
        "P", "Ç", "T", "K", "F", "H", "S", "Ş",
    ]

    /// Locative: Ev'de, Okul'da, Starbucks'ta.
    static func withLocative(_ name: String) -> String {
        guard let base = prepared(name) else { return name }
        return "\(base)'\(locativeEnding(base))"
    }

    /// Comitative / instrumental: Ahmet'le, Ayşe'yle.
    static func withComitative(_ name: String) -> String {
        guard let base = prepared(name) else { return name }
        return "\(base)'\(comitativeEnding(base))"
    }

    /// "You are at X" as a single Turkish word: Ev'desin, Okul'dasın.
    static func youAreAt(_ name: String) -> String {
        guard let base = prepared(name) else { return name }
        let ending = locativeEnding(base)
        let copula = ending.hasSuffix("e") ? "sin" : "sın"
        return "\(base)'\(ending)\(copula)"
    }

    /// Argument for catalog keys such as `"📍 %@ misin?"`.
    /// Turkish gets a locative form; other languages get the bare name.
    static func locativeArgument(_ name: String, locale: Locale = .current) -> String {
        isTurkish(locale) ? withLocative(name) : name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Argument for catalog keys such as `"%@. %@ işaretlensin mi?"`.
    static func youAreAtArgument(_ name: String, locale: Locale = .current) -> String {
        isTurkish(locale) ? youAreAt(name) : name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func locativeEnding(_ name: String) -> String {
        let consonant: Character = endsWithVoiceless(name) ? "t" : "d"
        let vowel: Character = isFront(name) ? "e" : "a"
        return String([consonant, vowel])
    }

    static func comitativeEnding(_ name: String) -> String {
        let buffer = endsWithVowel(name) ? "y" : ""
        let vowel: Character = isFront(name) ? "e" : "a"
        return "\(buffer)l\(vowel)"
    }

    private static func prepared(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isTurkish(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "tr"
    }

    private static func endsWithVoiceless(_ name: String) -> Bool {
        guard let last = name.last else { return false }
        return voiceless.contains(last)
    }

    private static func endsWithVowel(_ name: String) -> Bool {
        guard let last = name.last else { return false }
        return frontVowels.contains(last) || backVowels.contains(last)
    }

    private static func isFront(_ name: String) -> Bool {
        guard let vowel = lastVowel(name) else { return true }
        return frontVowels.contains(vowel)
    }

    private static func lastVowel(_ name: String) -> Character? {
        for character in name.reversed() {
            if frontVowels.contains(character) || backVowels.contains(character) { return character }
        }
        return nil
    }
}

enum LocationCopy {
    static func areYouAt(_ name: String, locale: Locale = .current) -> String {
        String(
            localized: "📍 \(TurkishSuffix.locativeArgument(name, locale: locale)) misin?",
            locale: locale)
    }

    static func geofencePrompt(place: String, goal: String, locale: Locale = .current) -> String {
        String(
            localized: "\(TurkishSuffix.youAreAtArgument(place, locale: locale)). \(goal) işaretlensin mi?",
            locale: locale)
    }

    static func geofenceTitle(
        place: String, goal: String, automatic: Bool, hideContent: Bool, locale: Locale = .current
    ) -> String {
        if hideContent {
            return automatic
                ? String(localized: "Hedef işaretlendi", locale: locale)
                : String(localized: "Bir hedefin yakınındasın", locale: locale)
        }
        return automatic
            ? String(localized: "\(goal) işaretlendi", locale: locale)
            : geofencePrompt(place: place, goal: goal, locale: locale)
    }
}
