import Foundation
import GoalTracking
import SwiftUI
import Testing

@testable import Kenet

/// Rules of the large-text fixes that need no screen: which sizes change a layout, and where the
/// lines are.
@MainActor @Suite
struct LargeTextRuleTests {
    /// The manşet takes its lines' height above the default size only; the default drawing stays.
    @Test func headlineTakesItsLinesAboveTheDefaultSize() {
        for size in [DynamicTypeSize.xSmall, .medium, .large] {
            #expect(!PageHeadline.takesItsLines(at: size))
        }
        for size in [DynamicTypeSize.xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility5] {
            #expect(PageHeadline.takesItsLines(at: size))
        }
    }

    /// The day timeline's hour goes above its cards at accessibility sizes, and at xxL and xxxL
    /// only in an axis narrower than a 320 pt row.
    @Test func dayTimelineStacksItsHourOnANarrowScreen() {
        let narrow = 320 - 2 * InkSpacing.margin
        let wide = 375 - 2 * InkSpacing.margin
        for size in [DynamicTypeSize.xxLarge, .xxxLarge] {
            #expect(TimelineDayBoard.stacksHour(width: narrow, dynamicTypeSize: size))
            #expect(!TimelineDayBoard.stacksHour(width: wide, dynamicTypeSize: size))
            #expect(!TimelineDayBoard.stacksHour(width: nil, dynamicTypeSize: size))
        }
        for size in [DynamicTypeSize.large, .xLarge] {
            #expect(!TimelineDayBoard.stacksHour(width: narrow, dynamicTypeSize: size))
        }
        for size in [DynamicTypeSize.accessibility1, .accessibility5] {
            #expect(TimelineDayBoard.stacksHour(width: wide, dynamicTypeSize: size))
            #expect(TimelineDayBoard.stacksHour(width: nil, dynamicTypeSize: size))
        }
    }

    @Test func wordFitScalesOnlyAWordWiderThanItsLine() {
        #expect(InkWordFit.words(in: "Bir süredir  görüşmediklerin") == ["Bir", "süredir", "görüşmediklerin"])
        #expect(InkWordFit.words(in: "  ").isEmpty)
        #expect(InkWordFit.scale(wordWidth: 100, available: 200) == 1)
        #expect(InkWordFit.scale(wordWidth: 300, available: nil) == 1)
        let scaled = InkWordFit.scale(wordWidth: 250, available: 200)
        #expect(scaled < 1 && scaled * 250 <= 200)
        #expect(InkWordFit.scale(wordWidth: 2000, available: 200) == InkWordFit.floor)
    }

    /// A span under 60 days (the 30 days of accessibility sizes) is named under the plot.
    @Test func shortChartSpanIsNamedUnderThePlot() {
        #expect(GoalValueChart.namesSpanBelow(span: GoalValueChart.span(isAccessibilitySize: true)))
        #expect(!GoalValueChart.namesSpanBelow(span: GoalValueChart.span(isAccessibilitySize: false)))
        #expect(GoalValueChart.spanText(from: "12 Eyl", to: "11 Eki") == "12 Eyl – 11 Eki")
    }

    /// The heatmap's day letters follow the given locale, Monday first.
    @Test func heatmapWeekdayLettersFollowTheLocale() {
        #expect(
            GoalHeatmapMetrics.weekdaySymbols(locale: Locale(identifier: "tr_TR")) == [
                "P", "S", "Ç", "P", "C", "C", "P",
            ])
        #expect(
            GoalHeatmapMetrics.weekdaySymbols(locale: Locale(identifier: "en_US")) == [
                "M", "T", "W", "T", "F", "S", "S",
            ])
    }

    /// A month label leaves 10 pt before the next label and 4 pt at the grid's edge.
    @Test func heatmapMonthLabelKeepsAGapBeforeTheNext() {
        #expect(GoalHeatmapMetrics.monthLabelWidth(weeks: 1, step: 30, isLast: false) == 20)
        #expect(GoalHeatmapMetrics.monthLabelWidth(weeks: 4, step: 30, isLast: false) == 110)
        #expect(GoalHeatmapMetrics.monthLabelWidth(weeks: 1, step: 30, isLast: true) == 26)
        #expect(GoalHeatmapMetrics.monthLabelWidth(weeks: 0, step: 30, isLast: false) == 0)
    }

    @Test func filterFieldIconSlotGrowsAtAccessibilitySizes() {
        for size in [DynamicTypeSize.medium, .large, .xxxLarge] {
            #expect(InkFilterFieldMetrics.iconSlot(dynamicTypeSize: size) == 36)
        }
        for size in [DynamicTypeSize.accessibility1, .accessibility5] {
            #expect(InkFilterFieldMetrics.iconSlot(dynamicTypeSize: size) == 48)
        }
        #expect(InkFilterFieldMetrics.iconSizeCeiling == .accessibility2)
    }
}

#if os(iOS)
    import UIKit

    /// The large-text fixes measured on hosted views, at the width of a 320 pt screen.
    @MainActor @Suite
    struct LargeTextRemainderTests {
        /// A 320 pt screen less the page margins.
        static let rowWidth: CGFloat = 320 - 2 * InkSpacing.margin
        nonisolated static let accessibilitySizes: [DynamicTypeSize] = [
            .accessibility1, .accessibility3, .accessibility5,
        ]

        // MARK: Manşet

        /// The manşet offered less height than its lines need still asks for all of them: a list
        /// row cut the title to "Deniz A…" at xxxL.
        @Test(arguments: [DynamicTypeSize.xxLarge, .xxxLarge, .accessibility1])
        func headlineKeepsItsLinesWhenOfferedLess(_ size: DynamicTypeSize) {
            let headline = PageHeadline(title: "Deniz Arıkan", byline: "Person · takma ad Deniz, Deniz abi")
            let width: CGFloat = 180
            let full = Self.size(of: headline, size: size, width: width, height: 4000).height
            let squeezed = Self.size(of: headline, size: size, width: width, height: 40).height
            #expect(squeezed == full, "the manşet gave up lines at \(size): \(squeezed) of \(full) pt")
        }

        // MARK: Zaman çizelgesi › Gün

        private static func hourRow(_ title: String, size: DynamicTypeSize) -> some View {
            let layout = TimelineDayBoard.hourLayout(dynamicTypeSize: size)
            return layout {
                InkTimeColumn(text: "16:00", minWidth: 48, alignment: .trailing)
                InkTimelineCard(title: title, meta: "16:00", kindLabel: "Olay")
            }
        }

        /// On a 320 pt screen at xxL and xxxL the hour is above the card, which then holds a word
        /// that broke beside the hour column.
        @Test(arguments: [DynamicTypeSize.xxLarge, .xxxLarge])
        func dayTimelineCardKeepsAWordOnANarrowScreen(_ size: DynamicTypeSize) {
            let word = Self.size(of: Self.hourRow("değerlendirmesi", size: size), size: size, width: Self.rowWidth)
            let letter = Self.size(of: Self.hourRow("d", size: size), size: size, width: Self.rowWidth)
            #expect(word.height == letter.height, "the word wrapped at \(size)")
            // Stacked: the row is taller than its card alone by the hour's line.
            let card = Self.size(
                of: InkTimelineCard(title: "d", meta: "16:00", kindLabel: "Olay"), size: size, width: Self.rowWidth)
            #expect(letter.height > card.height, "the hour stayed beside the card at \(size)")
        }

        /// On a 375 pt screen, and at L on a 320 pt one, the hour stays beside the card: the row is
        /// as tall as its card in the width the column leaves.
        @Test(arguments: [(DynamicTypeSize.xxLarge, 375.0), (.xxxLarge, 375.0), (.large, 320.0), (.xLarge, 320.0)])
        func dayTimelineKeepsItsHourColumn(_ size: DynamicTypeSize, screenWidth: Double) {
            let width = screenWidth - 2 * InkSpacing.margin
            let column = Self.size(
                of: InkTimeColumn(text: "16:00", minWidth: 48, alignment: .trailing), size: size, width: nil
            ).width
            let row = Self.size(of: Self.hourRow("Not", size: size), size: size, width: width).height
            let card = Self.size(
                of: InkTimelineCard(title: "Not", meta: "16:00", kindLabel: "Olay"), size: size,
                width: width - column - 10
            ).height
            #expect(row == card, "the hour left its column at \(size) on a \(Int(screenWidth)) pt screen")
        }

        // MARK: Kanban kartı

        /// The card's text on a phone column (240 pt less the card's padding): the box is above the
        /// text and a word wider than the card shrinks. It is then no taller than one letter.
        @Test(arguments: accessibilitySizes)
        func kanbanCardKeepsAWordWhole(_ size: DynamicTypeSize) {
            let width: CGFloat = KanbanBoardLayout.minimumColumnWidth - 24
            func title(_ text: String) -> some View {
                let layout = KanbanCard.titleLayout(stacks: size.isAccessibilitySize)
                return layout {
                    TaskBox(state: TaskBoxState(status: .todo, priority: nil), isDecorative: true)
                    Text(verbatim: text)
                        .font(
                            InkWordFit.font(
                                base: .ink.content, text: text, style: .content, size: size, available: width)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            let word = Self.size(of: title("değerlendirmesi"), size: size, width: width).height
            let letter = Self.size(of: title("d"), size: size, width: width).height
            #expect(word <= letter, "the word broke at \(size): \(word) pt, one line is \(letter) pt")
        }

        /// The measured word width is the drawn one: a text in the fitted font is one line high.
        @Test(arguments: accessibilitySizes)
        func wordFitFontHoldsItsWordOnOneLine(_ size: DynamicTypeSize) {
            for style in [InkWordFitStyle.content, .sectionTitle] {
                let base: Font = style == .content ? .ink.content : .ink.sectionTitle
                let width: CGFloat = 256
                func text(_ string: String) -> some View {
                    Text(verbatim: string)
                        .font(InkWordFit.font(base: base, text: string, style: style, size: size, available: width))
                }
                let word = Self.size(of: text("görüşmediklerin"), size: size, width: width).height
                let letter = Self.size(of: text("g"), size: size, width: width).height
                #expect(word <= letter, "\(style) broke its word at \(size)")
                // The widest word is not the one with the most letters: two words, two lines.
                let pair = Self.size(of: text("iiiiiiiiii mmmmmmm"), size: size, width: width).height
                #expect(pair <= 2 * letter + 2, "\(style) broke the wider, shorter word at \(size)")
            }
        }

        // MARK: Bölüm başlığı

        /// A section header in a narrow column (iPad list column, 256 pt) at accessibility sizes:
        /// the title measures its width in a window and shrinks until its longest word fits.
        @Test(arguments: accessibilitySizes)
        func sectionHeaderKeepsAWordWhole(_ size: DynamicTypeSize) async {
            let width: CGFloat = 256
            let word = await Self.windowHeight(
                of: SectionHeader(title: "görüşmediklerin", count: 4), size: size, width: width)
            let letter = await Self.windowHeight(of: SectionHeader(title: "g", count: 4), size: size, width: width)
            #expect(word <= letter, "the title broke its word at \(size): \(word) pt, one line is \(letter) pt")
        }

        /// A header made from a catalog key shrinks too: the key is read back to measure its word.
        @Test(arguments: [DynamicTypeSize.accessibility3, .accessibility5])
        func sectionHeaderFromAKeyKeepsAWordWhole(_ size: DynamicTypeSize) async {
            #expect(SectionHeader.catalogKey(of: "Hatırlatmalar") == "Hatırlatmalar")
            let width: CGFloat = 256
            let word = await Self.windowHeight(of: SectionHeader("Hatırlatmalar"), size: size, width: width)
            let letter = await Self.windowHeight(of: SectionHeader(title: "g"), size: size, width: width)
            #expect(word <= letter, "the title broke its word at \(size): \(word) pt, one line is \(letter) pt")
        }

        // MARK: Hedefler

        /// The legend outside the heatmap's scroll wraps inside a narrow card instead of running
        /// past it, and takes one line where it fits.
        @Test func heatmapLegendWrapsInANarrowCard() {
            let legend = GoalHeatmapLegend(period: .day, showsGrace: false)
            let wide = Self.size(of: legend, size: .xxxLarge, width: 900)
            let narrow = Self.size(of: legend, size: .xxxLarge, width: 220)
            #expect(narrow.height > wide.height)
            #expect(narrow.width <= 220)
            let fitted = UIHostingController(
                rootView: legend.environment(\.dynamicTypeSize, .accessibility3)
                    .environment(\.locale, Locale(identifier: "en_US"))
            ).sizeThatFits(in: CGSize(width: 220, height: 4000))
            #expect(fitted.width <= 220, "a legend title ran past the card at AX3: \(fitted.width) pt")
        }

        /// A month label one week wide has no room for itself and the gap before the next label.
        @Test func heatmapDropsAMonthLabelThatCrowdsTheNext() {
            let font = UIFont.preferredFont(forTextStyle: .footnote)
            let label = ("Ağu" as NSString).size(withAttributes: [.font: font]).width
            let step = GoalHeatmapMetrics.step(cellSize: 27)
            #expect(label > GoalHeatmapMetrics.monthLabelWidth(weeks: 1, step: step, isLast: false))
            #expect(label <= GoalHeatmapMetrics.monthLabelWidth(weeks: 2, step: step, isLast: false))
        }

        /// The goal card's name row from xxL up: the chip goes under a name that leaves it no room,
        /// whole, instead of being cut to "Hafta…" beside it.
        @Test(arguments: [DynamicTypeSize.xxLarge, .xxxLarge])
        func goalCardChipWrapsUnderTheName(_ size: DynamicTypeSize) {
            #expect(GoalListCard<EmptyView>.flowsTitle(at: size))
            #expect(!GoalListCard<EmptyView>.flowsTitle(at: .large))
            let name = Text(verbatim: "Spor salonu").font(.ink.content.weight(.semibold))
            let chip = TagChip(title: "Haftalık")
            let nameSize = Self.size(of: name, size: size, width: nil)
            let chipSize = Self.size(of: chip, size: size, width: nil)
            // Room for the name alone, not for the chip beside it.
            let width = nameSize.width + 8 + chipSize.width / 2
            let layout = GoalListCard<EmptyView>.titleLayout(flows: GoalListCard<EmptyView>.flowsTitle(at: size))
            let row = Self.size(
                of: layout {
                    name
                    chip
                }, size: size, width: width)
            #expect(abs(row.height - (nameSize.height + 4 + chipSize.height)) < 0.01, "the chip stayed beside the name")
        }

        // MARK: Süzgeç alanı

        /// The magnifier, drawn at up to AX2, is no wider than its slot at any text size.
        @Test(arguments: [
            DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility2, .accessibility5,
        ])
        func filterFieldIconFitsItsSlot(_ size: DynamicTypeSize) {
            let drawn = min(size, InkFilterFieldMetrics.iconSizeCeiling)
            let icon = Self.size(
                of: Image(systemName: "magnifyingglass").font(.body), size: drawn, width: nil)
            let slot = InkFilterFieldMetrics.iconSlot(dynamicTypeSize: size)
            #expect(icon.width <= slot, "the magnifier is \(icon.width) pt in a \(slot) pt slot at \(size)")
        }

        // MARK: Ölçüm

        private static func size(
            of view: some View, size: DynamicTypeSize, width: CGFloat?, height: CGFloat = 4000
        ) -> CGSize {
            let sized =
                view
                .frame(width: width)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: "tr_TR"))
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: width ?? 4000, height: height))
        }

        /// The view's height once it has measured itself in a window (state from its own geometry).
        private static func windowHeight(of view: some View, size: DynamicTypeSize, width: CGFloat) async -> CGFloat {
            let sized =
                view
                .frame(width: width)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: "tr_TR"))
            let host = UIHostingController(rootView: sized)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first else {
                Issue.record("no window scene")
                return 0
            }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
            window.rootViewController = host
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
                window.windowScene = nil
            }
            for _ in 0..<6 {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(30))
            }
            return host.sizeThatFits(in: CGSize(width: width, height: 4000)).height
        }
    }
#endif
