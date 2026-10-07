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
    private static let ones = ["", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz"]
    private static let tens = [
        "", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan",
    ]

    /// Locative: Ev'de, Okul'da, Starbucks'ta.
    static func withLocative(_ name: String) -> String {
        guard let base = prepared(name) else { return name }
        return "\(base)'\(locativeEnding(base))"
    }

    /// Ablative: Ocak'tan, Eylül'den, 2025'ten.
    static func withAblative(_ name: String) -> String {
        guard let base = prepared(name) else { return name }
        return "\(base)'\(ablativeEnding(base))"
    }

    /// Ablative for a cardinal whose spoken form drives vowel harmony (2025'ten, 2026'dan).
    static func withAblativeNumber(_ number: Int) -> String {
        "\(number)'\(ablativeEnding(forNumber: number))"
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

    /// Ablative ending (-den/-dan/-ten/-tan) for a spoken word stem.
    static func ablativeEnding(_ name: String) -> String {
        locativeEnding(name) + "n"
    }

    /// Ablative ending driven by the last spoken word of a cardinal number.
    static func ablativeEnding(forNumber number: Int) -> String {
        ablativeEnding(lastSpokenWord(of: number))
    }

    static func comitativeEnding(_ name: String) -> String {
        let buffer = endsWithVowel(name) ? "y" : ""
        let vowel: Character = isFront(name) ? "e" : "a"
        return "\(buffer)l\(vowel)"
    }

    static func isTurkish(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "tr"
    }

    /// Last word in the Turkish reading of a non-negative cardinal (for suffix harmony).
    static func lastSpokenWord(of number: Int) -> String {
        let value = abs(number)
        if value == 0 { return "sıfır" }
        let lower = value % 1000
        if lower != 0 { return lastSpokenWordBelow1000(lower) }
        if (value / 1000) % 1000 != 0 { return "bin" }
        return "milyon"
    }

    private static func lastSpokenWordBelow1000(_ value: Int) -> String {
        let rem100 = value % 100
        if rem100 != 0 { return lastSpokenWordBelow100(rem100) }
        return "yüz"
    }

    private static func lastSpokenWordBelow100(_ value: Int) -> String {
        if value < 10 { return ones[value] }
        if value < 20 { return value == 10 ? "on" : ones[value - 10] }
        if value % 10 == 0 { return tens[value / 10] }
        return ones[value % 10]
    }

    private static func prepared(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
