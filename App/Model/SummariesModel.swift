import Foundation
import GoalTracking
import Observation
import Summaries
import VaultFormat

@MainActor @Observable
final class SummariesModel {
    let store: IndexStore
    var period: SummaryPeriod
    private(set) var day: CalendarDate
    private(set) var summary: PeriodSummary?
    private(set) var isLoading = false
    private(set) var errorText: String?
    private let today: () -> CalendarDate
    @ObservationIgnored private var request = UUID()

    init(
        store: IndexStore, today: @escaping () -> CalendarDate = { LocalDay.today() },
        period: SummaryPeriod = .week, day: CalendarDate? = nil
    ) {
        self.store = store
        self.today = today
        self.period = period
        self.day = day ?? today()
    }
    var range: ClosedRange<CalendarDate> { period.bounds(containing: day) }
    /// What a load depends on. Today is part of it, so a page left open past midnight loads again.
    var requestKey: String {
        period.rawValue + "|" + day.description + "|" + today().description + "|" + (store.vaultURL?.path ?? "")
            + "|" + String(store.lastUpdated?.timeIntervalSince1970 ?? 0)
    }
    /// The shown period holds today.
    var isCurrent: Bool { range.contains(today()) }
    var canGoPrevious: Bool { period.previous(containing: day) != nil }
    /// A period after today's has nothing to count yet.
    var canGoNext: Bool { period.next(containing: day).map { $0.lowerBound <= today() } ?? false }
    func previous() { if let range = period.previous(containing: day) { day = range.lowerBound } }
    func next() { if canGoNext, let range = period.next(containing: day) { day = range.lowerBound } }
    func current() { day = today() }
    func reset() {
        request = UUID()
        summary = nil
        errorText = nil
        isLoading = false
        day = today()
    }

    func load() async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        let period = period
        let day = day
        isLoading = true
        errorText = nil
        // The shown content stays until the first answer, for the same period and for another one alike.
        defer { if request == id { isLoading = false } }
        do {
            let result = try await store.periodSummary(period, containing: day, today: today())
            guard request == id, root == store.vaultURL, self.period == period, self.day == day, !Task.isCancelled
            else { return }
            summary = result
        } catch {
            guard request == id, root == store.vaultURL, self.period == period, self.day == day, !Task.isCancelled
            else { return }
            errorText = DayEditError.message(for: error)
        }
    }
}

/// Words and rhythm columns of the Summaries screen; `locale` selects the catalog language.
enum SummaryPresentation {
    /// "önceki haftaya göre +4", "önceki haftayla aynı". A running period names the same date instead.
    static func change(_ value: Int, period: SummaryPeriod, isRunning: Bool, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        if value == 0 {
            switch (period, isRunning) {
            case (.week, false): return String(localized: "önceki haftayla aynı", bundle: bundle, locale: locale)
            case (.month, false): return String(localized: "önceki ayla aynı", bundle: bundle, locale: locale)
            case (.year, false): return String(localized: "önceki yılla aynı", bundle: bundle, locale: locale)
            case (.week, true):
                return String(localized: "geçen haftanın aynı günüyle aynı", bundle: bundle, locale: locale)
            case (.month, true):
                return String(localized: "geçen ayın aynı tarihiyle aynı", bundle: bundle, locale: locale)
            case (.year, true):
                return String(localized: "geçen yılın aynı tarihiyle aynı", bundle: bundle, locale: locale)
            }
        }
        return compared(signed(Double(value), locale: locale), period: period, isRunning: isRunning, locale: locale)
    }

    /// "+12", "−3,5": the sign and the number; a unit follows when given.
    static func signed(_ value: Double, unit: String? = nil, locale: Locale) -> String {
        let number = abs(value).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        let text = (value > 0 ? "+" : "−") + number
        guard let unit, !unit.isEmpty else { return text }
        return text + " " + unit
    }

    /// The signed change named against the period it is compared with.
    private static func compared(_ signed: String, period: SummaryPeriod, isRunning: Bool, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        switch (period, isRunning) {
        case (.week, false): return String(localized: "önceki haftaya göre \(signed)", bundle: bundle, locale: locale)
        case (.month, false): return String(localized: "önceki aya göre \(signed)", bundle: bundle, locale: locale)
        case (.year, false): return String(localized: "önceki yıla göre \(signed)", bundle: bundle, locale: locale)
        case (.week, true):
            return String(localized: "geçen haftanın aynı gününe göre \(signed)", bundle: bundle, locale: locale)
        case (.month, true):
            return String(localized: "geçen ayın aynı tarihine göre \(signed)", bundle: bundle, locale: locale)
        case (.year, true):
            return String(localized: "geçen yılın aynı tarihine göre \(signed)", bundle: bundle, locale: locale)
        }
    }

    /// Open tasks of an empty period in one line.
    static func carried(overdue: Int, undated: Int, locale: Locale) -> String {
        String(
            localized: "Açık görevler: \(overdue) devreden, \(undated) tarihsiz",
            bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    static func previousTitle(_ period: SummaryPeriod, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        return switch period {
        case .week: String(localized: "Önceki hafta", bundle: bundle, locale: locale)
        case .month: String(localized: "Önceki ay", bundle: bundle, locale: locale)
        case .year: String(localized: "Önceki yıl", bundle: bundle, locale: locale)
        }
    }

    static func mark(_ writing: SummaryUnit.Writing) -> RhythmMark {
        switch writing {
        case .full: .full
        case .partial: .partial
        case .none: .none
        case .notStarted: .notStarted
        }
    }

    static func markTitle(_ mark: RhythmMark, period: SummaryPeriod, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        switch mark {
        case .full:
            return period == .week
                ? String(localized: "Yazıldı", bundle: bundle, locale: locale)
                : String(localized: "Günlerin yarısı ya da fazlası yazıldı", bundle: bundle, locale: locale)
        case .partial: return String(localized: "Yarıdan azı yazıldı", bundle: bundle, locale: locale)
        case .none: return String(localized: "Yazılmadı", bundle: bundle, locale: locale)
        case .notStarted: return ""
        }
    }

    static func legend(_ period: SummaryPeriod, locale: Locale) -> [RhythmLegendItem] {
        let marks: [RhythmMark] = period == .week ? [.full, .none] : [.full, .partial, .none]
        let events = String(localized: "Olay sayısı", bundle: PresentationLocalization.bundle(locale), locale: locale)
        return [
            RhythmLegendItem(swatch: .current, title: events),
            RhythmLegendItem(swatch: .previous, title: previousTitle(period, locale: locale)),
        ] + marks.map { RhythmLegendItem(swatch: .mark($0), title: markTitle($0, period: period, locale: locale)) }
    }

    /// One column per unit; the previous period's unit at the same position stands behind it.
    static func rhythm(_ summary: PeriodSummary, locale: Locale) -> [RhythmStripItem] {
        let bundle = PresentationLocalization.bundle(locale)
        return summary.units.enumerated().map { index, unit in
            let start = LocalDay.instant(for: unit.range.lowerBound)
            let label: String
            let spoken: String
            switch summary.period {
            case .week:
                label = start.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated))
                spoken = start.formatted(Date.FormatStyle(locale: locale).weekday(.wide).day().month(.wide))
            case .month:
                label = "\(unit.range.lowerBound.day)–\(unit.range.upperBound.day)"
                spoken = label + " " + start.formatted(Date.FormatStyle(locale: locale).month(.wide))
            case .year:
                label = start.formatted(Date.FormatStyle(locale: locale).month(.abbreviated))
                spoken = start.formatted(Date.FormatStyle(locale: locale).month(.wide))
            }
            let previous = index < summary.previousUnits.count ? summary.previousUnits[index].events : nil
            let mark = mark(unit.writing)
            var parts: [String] = []
            if mark != .notStarted {
                parts.append(String(localized: "\(unit.events) olay", bundle: bundle, locale: locale))
            }
            if let previous {
                parts.append(String(localized: "önceki dönemde \(previous)", bundle: bundle, locale: locale))
            }
            if mark != .notStarted { parts.append(markTitle(mark, period: summary.period, locale: locale)) }
            return RhythmStripItem(
                id: index, label: label, spokenLabel: spoken, value: unit.events, previous: previous, mark: mark,
                spokenValue: parts.joined(separator: ", "))
        }
    }

    /// Meta under a goal's name: the chain while the period runs or at its end, the score, or the year.
    static func goalMeta(_ goal: SummaryGoal, isRunning: Bool, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        if goal.definition.kind == .milestone {
            if let date = goal.completionDate {
                return LocalDay.instant(for: date).formatted(Date.FormatStyle(locale: locale).day().month().year())
            }
            return String(localized: "Yapılmadı", bundle: bundle, locale: locale)
        }
        if goal.definition.period == .year { return String(localized: "Yıl başından", bundle: bundle, locale: locale) }
        let streak =
            isRunning
            ? String(localized: "Güncel zincir: \(goal.streak)", bundle: bundle, locale: locale)
            : String(localized: "Dönem sonu zinciri: \(goal.streak)", bundle: bundle, locale: locale)
        guard goal.definition.period == .day, let score = goal.score else { return streak }
        return streak + "\n" + GoalScoreCopy.sentence(score, bundle: bundle, locale: locale)
    }

    /// Under a goal row: the progress change and the chain change, each only when it is not zero.
    /// Nil when both are zero, so the row gets no empty line. A milestone has neither.
    static func goalChange(_ goal: SummaryGoal, period: SummaryPeriod, isRunning: Bool, locale: Locale) -> String? {
        guard goal.definition.kind != .milestone else { return nil }
        var parts: [String] = []
        if goal.change != 0 {
            parts.append(
                compared(
                    signed(goal.change, unit: goal.definition.unit, locale: locale), period: period,
                    isRunning: isRunning, locale: locale))
        }
        if goal.definition.period != .year, goal.streakChange != 0 {
            let chain = signed(Double(goal.streakChange), locale: locale)
            parts.append(
                String(localized: "zincir \(chain)", bundle: PresentationLocalization.bundle(locale), locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "İlk kez:" names: at most 10, then how many more.
    static func firstNames(_ firsts: [SummaryFirstMention], kind: SummaryInput.Entity.Kind, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        let names = firsts.map(\.name)
        let list: String
        if names.count <= 10 {
            list = names.formatted(.list(type: .and).locale(locale))
        } else {
            let shown = names.prefix(10).joined(separator: ", ")
            let more = names.count - 10
            list =
                kind == .person
                ? String(localized: "\(shown) ve \(more) kişi daha", bundle: bundle, locale: locale)
                : String(localized: "\(shown) ve \(more) konum daha", bundle: bundle, locale: locale)
        }
        return String(localized: "İlk kez: \(list)", bundle: bundle, locale: locale)
    }

    /// VoiceOver label of a name chip: the name, the mentions with their unit, and a first mention.
    static func chipLabel(name: String, count: Int, isFirst: Bool, locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        return isFirst
            ? String(localized: "\(name), \(count) geçiş, ilk kez", bundle: bundle, locale: locale)
            : String(localized: "\(name), \(count) geçiş", bundle: bundle, locale: locale)
    }

    static func goalValue(_ goal: SummaryGoal, locale: Locale) -> String? {
        guard goal.definition.kind != .milestone else { return nil }
        var text =
            goal.progress.done.formatted(.number.locale(locale)) + "/"
            + goal.progress.target.formatted(.number.locale(locale))
        if let unit = goal.definition.unit, !unit.isEmpty { text += " " + unit }
        return text
    }

    static func goalFraction(_ goal: SummaryGoal) -> Double {
        if goal.definition.kind == .milestone { return goal.completionDate == nil ? 0 : 1 }
        return InkProgressMath.ratio(done: goal.progress.done, target: goal.progress.target)
    }
}
