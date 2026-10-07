import Foundation
import Testing

@testable import Journal

struct TurkishSuffixTests {
    private let turkish = Locale(identifier: "tr_TR")
    private let english = Locale(identifier: "en_US")

    @Test func locativeTable() {
        let cases: [(String, String)] = [
            ("Ev", "Ev'de"),
            ("Okul", "Okul'da"),
            ("İstanbul", "İstanbul'da"),
            ("Ankara", "Ankara'da"),
            ("Kadıköy", "Kadıköy'de"),
            ("Starbucks", "Starbucks'ta"),
            ("Park", "Park'ta"),
            ("Garaj", "Garaj'da"),
            ("A", "A'da"),
            ("", ""),
            ("  Ev  ", "Ev'de"),
            ("XYZ", "XYZ'de"),
        ]
        for (name, expected) in cases {
            #expect(TurkishSuffix.withLocative(name) == expected, "locative for \(name)")
        }
    }

    @Test func comitativeTable() {
        let cases: [(String, String)] = [
            ("Ahmet", "Ahmet'le"),
            ("Ayşe", "Ayşe'yle"),
            ("Ali", "Ali'yle"),
            ("Mert", "Mert'le"),
        ]
        for (name, expected) in cases {
            #expect(TurkishSuffix.withComitative(name) == expected, "comitative for \(name)")
        }
    }

    @Test func ablativeTableForWordsAndNumbers() {
        let months: [(String, String)] = [
            ("Ocak", "Ocak'tan"), ("Şubat", "Şubat'tan"), ("Mart", "Mart'tan"), ("Nisan", "Nisan'dan"),
            ("Mayıs", "Mayıs'tan"), ("Haziran", "Haziran'dan"), ("Temmuz", "Temmuz'dan"),
            ("Ağustos", "Ağustos'tan"), ("Eylül", "Eylül'den"), ("Ekim", "Ekim'den"), ("Kasım", "Kasım'dan"),
            ("Aralık", "Aralık'tan"),
        ]
        for (name, expected) in months {
            #expect(TurkishSuffix.withAblative(name) == expected, "ablative for \(name)")
        }
        let years: [(Int, String)] = [
            (2000, "2000'den"), (2019, "2019'dan"), (2023, "2023'ten"), (2024, "2024'ten"),
            (2025, "2025'ten"), (2026, "2026'dan"), (2030, "2030'dan"), (2040, "2040'tan"),
        ]
        for (year, expected) in years {
            #expect(TurkishSuffix.withAblativeNumber(year) == expected, "ablative for \(year)")
        }
    }

    @Test func youAreAtUsesLocativeAndCopula() {
        #expect(TurkishSuffix.youAreAt("Ev") == "Ev'desin")
        #expect(TurkishSuffix.youAreAt("Okul") == "Okul'dasın")
        #expect(TurkishSuffix.youAreAt("Starbucks") == "Starbucks'tasın")
    }

    @Test func locationCopyUsesSuffixOnlyInTurkish() {
        #expect(LocationCopy.areYouAt("Ev", locale: turkish).contains("Ev'de"))
        #expect(!LocationCopy.areYouAt("Okul", locale: turkish).contains("Okul'te"))
        #expect(LocationCopy.areYouAt("Okul", locale: turkish).contains("Okul'da"))
        let englishLabel = LocationCopy.areYouAt("Okul", locale: english)
        #expect(englishLabel.contains("Okul"))
        #expect(!englishLabel.contains("'"))
        let prompt = LocationCopy.geofencePrompt(place: "Ev", goal: "Yürüyüş", locale: turkish)
        #expect(prompt.contains("Ev'desin"))
        #expect(!prompt.contains("'ndasın"))
        let englishPrompt = LocationCopy.geofencePrompt(place: "Home", goal: "Walk", locale: english)
        #expect(englishPrompt.contains("Home"))
        #expect(englishPrompt.contains("Walk"))
        #expect(!englishPrompt.contains("'ndasın"))
        let hidden = LocationCopy.geofenceTitle(
            place: "Ev", goal: "Yürüyüş", automatic: false, hideContent: true, locale: turkish)
        #expect(hidden == String(localized: "Bir hedefin yakınındasın", locale: turkish))
        #expect(!hidden.contains("Ev"))
        #expect(!hidden.contains("Yürüyüş"))
        let hiddenAutomatic = LocationCopy.geofenceTitle(
            place: "Ev", goal: "Yürüyüş", automatic: true, hideContent: true, locale: turkish)
        #expect(hiddenAutomatic == String(localized: "Hedef işaretlendi", locale: turkish))
        #expect(!hiddenAutomatic.contains("Yürüyüş"))
        let visible = LocationCopy.geofenceTitle(
            place: "Ev", goal: "Yürüyüş", automatic: false, hideContent: false, locale: turkish)
        #expect(visible == prompt)
    }
}
