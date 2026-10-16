import Summaries
import SwiftUI
import VaultFormat

/// "Haftanın günleri" section on Özetler (Month and Year tabs): seven Monday…Sunday written-day
/// ratio rows with a 1 px framed strip (`Color.ink.accent` on `Color.ink.well`), `"3/4"` counter
/// on the right, and a leading dot mark on the highest-ratio weekday.
struct WeekdayDistributionView: View {
    let distribution: WeekdayDistribution

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .footnote) private var markSize: CGFloat = 6
    @ScaledMetric(relativeTo: .footnote) private var ratioBarHeight: CGFloat = 10
    @ScaledMetric(relativeTo: .footnote) private var dayColumnWidth: CGFloat = 78
    @ScaledMetric(relativeTo: .footnote) private var countColumnWidth: CGFloat = 42

    private var resolvedLocale: Locale { PresentationLocalization.resolvedLocale(locale) }
    private var bundle: Bundle { PresentationLocalization.bundle(resolvedLocale) }

    /// 2026-01-05 is a Monday (`weekday == 0`).
    private static let referenceMonday = CalendarDate("2026-01-05")!

    var body: some View {
        if distribution.entries.contains(where: { $0.totalDays > 0 }) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "Haftanın günleri", bundle: bundle, locale: resolvedLocale))
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityRows
                } else {
                    regularRows
                }
            }
        }
    }

    private var regularRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(distribution.entries) { entry in
                let isLeading = entry.weekday == distribution.leadingWeekday
                HStack(alignment: .center, spacing: 8) {
                    if isLeading {
                        Circle()
                            .fill(Color.ink.text)
                            .frame(width: markSize, height: markSize)
                    } else {
                        Color.clear
                            .frame(width: markSize, height: markSize)
                    }
                    Text(verbatim: Self.weekdayName(entry.weekday, locale: resolvedLocale))
                        .font(isLeading ? .ink.meta.weight(.semibold) : .ink.meta)
                        .foregroundStyle(Color.ink.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: dayColumnWidth, alignment: .leading)
                    ratioBar(entry: entry, height: ratioBarHeight)
                    Text(verbatim: Self.fractionText(entry, locale: resolvedLocale))
                        .font(isLeading ? .ink.meta.weight(.semibold) : .ink.meta)
                        .monospacedDigit()
                        .foregroundStyle(isLeading ? Color.ink.text : Color.ink.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: countColumnWidth, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Self.spokenRow(entry, locale: resolvedLocale)))
            }
        }
    }

    private var accessibilityRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(distribution.entries) { entry in
                let isLeading = entry.weekday == distribution.leadingWeekday
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if isLeading {
                            Circle()
                                .fill(Color.ink.text)
                                .frame(width: markSize, height: markSize)
                        }
                        Text(verbatim: Self.weekdayName(entry.weekday, locale: resolvedLocale))
                            .font(isLeading ? .ink.meta.weight(.semibold) : .ink.meta)
                            .foregroundStyle(Color.ink.text)
                        Spacer(minLength: 8)
                        Text(verbatim: Self.fractionText(entry, locale: resolvedLocale))
                            .font(isLeading ? .ink.value.weight(.semibold) : .ink.value)
                            .monospacedDigit()
                            .foregroundStyle(isLeading ? Color.ink.text : Color.ink.secondaryText)
                    }
                    ratioBar(entry: entry, height: 12)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: Self.spokenRow(entry, locale: resolvedLocale)))
            }
        }
    }

    private func ratioBar(entry: WeekdayDistribution.Entry, height: CGFloat) -> some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
            let fillWidth =
                entry.totalDays > 0
                ? max(
                    entry.writtenDays > 0 ? 3 : 0,
                    geo.size.width * CGFloat(entry.writtenDays) / CGFloat(entry.totalDays)
                )
                : 0
            ZStack(alignment: .leading) {
                shape.fill(Color.ink.well)
                if fillWidth > 0 {
                    Rectangle()
                        .fill(Color.ink.accent)
                        .frame(width: min(geo.size.width, fillWidth))
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.ink.control, lineWidth: InkStroke.hairline(scale: displayScale))
            }
        }
        .frame(height: height)
    }

    // MARK: - Presentation & Localization

    static func weekdayName(_ weekday: Int, locale: Locale) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        guard let date = referenceMonday.addingDays(weekday) else { return "" }
        return LocalDay.instant(for: date).formatted(
            Date.FormatStyle(locale: resolved).weekday(.wide))
    }

    static func fractionText(_ entry: WeekdayDistribution.Entry, locale: Locale) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        return entry.writtenDays.formatted(.number.grouping(.never).locale(resolved)) + "/"
            + entry.totalDays.formatted(.number.grouping(.never).locale(resolved))
    }

    static func spokenRow(_ entry: WeekdayDistribution.Entry, locale: Locale) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let bundle = PresentationLocalization.bundle(resolved)
        let name = weekdayName(entry.weekday, locale: resolved)
        let written = possessedNumber(entry.writtenDays, locale: resolved)
        return String(
            localized: "\(name): \(entry.totalDays) günün \(written) yazıldı",
            bundle: bundle, locale: resolved)
    }

    /// The number with its Turkish third-person possessive ("4'ü", "2'si", "90'ı"); other languages get digits.
    private static func possessedNumber(_ number: Int, locale: Locale) -> String {
        let digits = number.formatted(.number.grouping(.never).locale(locale))
        guard TurkishSuffix.isTurkish(locale) else { return digits }
        let word = TurkishSuffix.lastSpokenWord(of: number)
        let lastVowel = word.last { "aıoueiöü".contains($0) }
        let vowel: String =
            switch lastVowel {
            case "a", "ı": "ı"
            case "o", "u": "u"
            case "ö", "ü": "ü"
            default: "i"
            }
        let buffer = word.last == lastVowel ? "s" : ""
        return "\(digits)'\(buffer)\(vowel)"
    }
}
