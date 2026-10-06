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
    }
}
