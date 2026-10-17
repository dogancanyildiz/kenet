import Foundation
import GoalTracking

/// Templates only prefill the creation form; their identity and symbol are never persisted.
struct GoalTemplate: Identifiable, Hashable, Sendable {
    let id: String
    /// String Catalog key, resolved when the form is presented.
    let name: String
    let symbol: String
    let kind: GoalKind
    let period: GoalPeriod
    let target: Int
    private let unitKey: String?

    var unit: String? { localizedUnit() }

    func localizedName(locale: Locale = .current) -> String {
        String(
            localized: String.LocalizationValue(name),
            bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    func localizedUnit(locale: Locale = .current) -> String? {
        unitKey.map {
            String(
                localized: String.LocalizationValue($0),
                bundle: PresentationLocalization.bundle(locale), locale: locale)
        }
    }

    func summary(locale: Locale = .current) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        if let unit = localizedUnit(locale: locale) {
            return String(localized: "\(target) \(unit) / gün", bundle: bundle, locale: locale)
        }
        if period == .week {
            return String(localized: "Haftada \(target)", bundle: bundle, locale: locale)
        }
        return String(localized: "Her gün", bundle: bundle, locale: locale)
    }

    static let all: [GoalTemplate] = [
        .init(
            id: "water", name: "Su iç", symbol: "drop.fill", kind: .number, period: .day, target: 8, unitKey: "bardak"),
        .init(
            id: "read", name: "Kitap oku", symbol: "book.fill", kind: .number, period: .day, target: 20,
            unitKey: "sayfa"),
        .init(
            id: "exercise", name: "Egzersiz yap", symbol: "figure.run", kind: .number, period: .day, target: 30,
            unitKey: "dk"),
        .init(
            id: "walk", name: "Yürü", symbol: "figure.walk", kind: .number, period: .day, target: 10000, unitKey: "adım"
        ),
        .init(
            id: "meditate", name: "Meditasyon", symbol: "figure.mind.and.body", kind: .number, period: .day, target: 10,
            unitKey: "dk"),
        .init(
            id: "wake", name: "Erken kalk", symbol: "sunrise.fill", kind: .boolean, period: .day, target: 1,
            unitKey: nil),
        .init(
            id: "vitamins", name: "Vitamin al", symbol: "pills.fill", kind: .boolean, period: .day, target: 1,
            unitKey: nil),
        .init(
            id: "floss", name: "Diş ipi kullan", symbol: "mouth.fill", kind: .boolean, period: .day, target: 1,
            unitKey: nil),
        .init(
            id: "nosmoking", name: "Sigara içme", symbol: "nosign", kind: .boolean, period: .day, target: 1,
            unitKey: nil),
        .init(
            id: "nosugar", name: "Şekersiz gün", symbol: "carrot.fill", kind: .boolean, period: .day, target: 1,
            unitKey: nil),
        .init(
            id: "language", name: "Dil çalış", symbol: "character.book.closed.fill", kind: .number, period: .day,
            target: 15, unitKey: "dk"),
        .init(
            id: "sleep", name: "Uyu", symbol: "bed.double.fill", kind: .number, period: .day, target: 8, unitKey: "saat"
        ),
        .init(
            id: "tidy", name: "Temizlik yap", symbol: "sparkles", kind: .number, period: .day, target: 10, unitKey: "dk"
        ),
        .init(
            id: "nospend", name: "Harcamasız gün", symbol: "banknote.fill", kind: .boolean, period: .day, target: 1,
            unitKey: nil),
        .init(
            id: "gym", name: "Spor salonuna git", symbol: "dumbbell.fill", kind: .boolean, period: .week, target: 3,
            unitKey: nil),
    ]
}
