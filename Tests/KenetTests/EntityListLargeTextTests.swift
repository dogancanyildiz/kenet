import Foundation
import Summaries
import SwiftUI
import Testing
import VaultFormat
import VaultIndex

@testable import Kenet

/// The Kişiler list's counts in both languages: English takes its plural form ("1 day", never
/// "1 days"), Turkish keeps one form.
@MainActor @Suite
struct EntityListPluralTests {
    private static let turkish = Locale(identifier: "tr_TR")
    private static let english = Locale(identifier: "en_US")

    @Test func yearDaysLabelTakesItsPluralForm() {
        #expect(EntityRowPresentation.yearDaysLabel(days: 1, locale: Self.english) == "1 day in the last 12 months")
        #expect(EntityRowPresentation.yearDaysLabel(days: 5, locale: Self.english) == "5 days in the last 12 months")
        #expect(EntityRowPresentation.yearDaysLabel(days: 1, locale: Self.turkish) == "Son 12 ayda 1 gün")
        #expect(EntityRowPresentation.yearDaysLabel(days: 5, locale: Self.turkish) == "Son 12 ayda 5 gün")
    }

    /// The average interval is formatted text ("2,8"); an interval of exactly one day reads
    /// "1 day" in English.
    @Test func averageIntervalTakesItsPluralForm() throws {
        let today = try #require(CalendarDate("2026-10-04"))
        // Five days in a row: an average interval of one day.
        let daily = (0..<5).compactMap { today.addingDays(-$0) }
        let density = EntityMentionDensity.compute(days: daily, today: today)
        #expect(density.recentDayCount == 5 && density.averageInterval == 1)
        let english = try #require(EntityInsights.presentationMentions(density: density, locale: Self.english))
        #expect(english.recentIntervalText == "5 days in the last 90 days · average interval 1 day")
        let turkish = try #require(EntityInsights.presentationMentions(density: density, locale: Self.turkish))
        #expect(turkish.recentIntervalText == "Son 90 günde 5 gün · ortalama aralık 1 gün")

        // Every fifth day: five days apart.
        let sparse = (0..<5).compactMap { today.addingDays(-5 * $0) }
        let sparseDensity = EntityMentionDensity.compute(days: sparse, today: today)
        #expect(sparseDensity.averageInterval == 5)
        let sparseEnglish = try #require(
            EntityInsights.presentationMentions(density: sparseDensity, locale: Self.english))
        #expect(sparseEnglish.recentIntervalText == "5 days in the last 90 days · average interval 5 days")
        let sparseTurkish = try #require(
            EntityInsights.presentationMentions(density: sparseDensity, locale: Self.turkish))
        #expect(sparseTurkish.recentIntervalText == "Son 90 günde 5 gün · ortalama aralık 5 gün")
    }
}

#if os(iOS)
    /// The Kişiler column's row in the iPad's narrow list column: at every text size the name
    /// keeps a whole word on one line. Beside the scaled badge and the day count the name was
    /// left about 95 pt at AX3 and broke mid-word ("Arıka / n").
    @MainActor @Suite
    struct EntityListLargeTextTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5,
        ]
        /// The list column of the 13-inch iPad in landscape at AX3, less the row insets.
        static let columnWidth: CGFloat = 288

        @Test(arguments: sizes)
        func columnRowKeepsAWordOnOneLine(_ size: DynamicTypeSize) throws {
            let today = try #require(CalendarDate("2026-09-20"))
            let activity = EntityListActivity(
                lastEncounter: today, recentDays: (0..<12).compactMap { today.addingDays(-$0) }, relationCount: 2)
            func row(_ name: String) -> some View {
                EntityRow(
                    entity: EntitySummary(
                        id: "people/\(name).md", kind: "person", name: name, qualifier: nil, aliases: [],
                        incomingLinks: 0),
                    activity: activity
                )
                .environment(\.shellKind, .split)
            }
            let word = Self.height(of: row("Arıkan"), size: size)
            let letter = Self.height(of: row("A"), size: size)
            #expect(word == letter, "the name wrapped at \(size)")
        }

        /// The create button keeps its title's words whole beside the "…" menu: when the two do
        /// not fit, the menu goes under the title instead of squeezing it ("New per- / son").
        @Test func tightRowStacksOnlyWhenAsked() {
            func height(stacks: Bool, width: CGFloat) -> CGFloat {
                let view = LeadingTrailingRowLayout(spacing: 12, stacksWhenTight: stacks) {
                    Color.clear.frame(width: 100, height: 30)
                    Color.clear.frame(width: 44, height: 44)
                }
                return UIHostingController(rootView: view.frame(width: width))
                    .sizeThatFits(in: CGSize(width: width, height: 4000)).height
            }
            #expect(height(stacks: true, width: 200) == 44)
            #expect(height(stacks: true, width: 150) == 74)
            #expect(height(stacks: false, width: 150) == 44)
        }

        private static func height(of view: some View, size: DynamicTypeSize) -> CGFloat {
            let sized =
                view
                .frame(width: columnWidth)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: "tr_TR"))
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: columnWidth, height: 4000)).height
        }
    }
#endif
