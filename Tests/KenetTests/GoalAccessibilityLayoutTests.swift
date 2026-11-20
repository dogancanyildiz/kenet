#if os(iOS)
    import GoalTracking
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Kenet

    /// The goal cards leave the name room for a whole word on a 320 pt screen at every text size.
    /// Beside the period chip and the "+" the name broke mid-word ("Es- / neme", AX1 and up) and the
    /// card asked for more than the screen's width, so the list drew it past both edges (AX3).
    @MainActor @Suite
    struct GoalAccessibilityLayoutTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5,
        ]
        /// A 320 pt screen less the page margins.
        static let cardWidth: CGFloat = 320 - 2 * InkSpacing.margin
        private static let day = CalendarDate("2026-09-20")!
        private static let locale = Locale(identifier: "tr_TR")

        private static func goal(_ name: String) -> GoalDefinition {
            GoalDefinition(
                id: "goals/\(name).md", key: "esneme", name: name, period: .day, kind: .boolean, target: 1)!
        }

        /// A daily goal with a streak, a score and two chain days: every line of the card is drawn.
        private static let status = GoalStatus(
            periodStart: day, periodEnd: day, progress: GoalAmount(done: 0, target: 1), streak: 64,
            longestStreak: 64, isPendingToday: true, score: 90, yearDone: 64, yearProgress: nil,
            graceDaysAvailable: 2)

        private static func listCard(_ name: String) -> some View {
            GoalListCard(
                goal: goal(name), status: status, day: day, logs: [], canEdit: true, markedToday: false,
                markReadOnly: false, locale: locale, onOpen: nil, opensDetail: false, detail: { EmptyView() },
                onIncrement: {}, onEnterAmount: {}, onUnmark: {})
        }

        private static func columnRow(_ name: String) -> some View {
            GoalColumnRow(
                goal: goal(name), status: status, day: day, logs: [], locale: locale, isDisabled: false,
                markedToday: false, onOpen: {})
        }

        /// The name stays on one line. The card is then as tall as one with a one-letter name, or
        /// taller by exactly the chip's own line when the chip wrapped under the name; a name broken
        /// into two lines gives another height.
        @Test(arguments: sizes)
        func listCardKeepsTheNameOnOneLine(_ size: DynamicTypeSize) {
            let word = Self.height(of: Self.listCard("Esneme"), size: size)
            let letter = Self.height(of: Self.listCard("E"), size: size)
            let name = Self.height(of: Text(verbatim: "E").font(.ink.content.weight(.semibold)), size: size)
            let chip = Self.height(
                of: TagChip(title: GoalListPresentation.periodChip(.day, locale: Self.locale)), size: size)
            let chipWrapped = letter - max(name, chip) + name + 4 + chip
            #expect(
                abs(word - letter) < 0.01 || abs(word - chipWrapped) < 0.01,
                "the name wrapped at \(size): \(word) pt, one line is \(letter) or \(chipWrapped) pt")
        }

        @Test(arguments: sizes)
        func listCardFitsTheScreen(_ size: DynamicTypeSize) {
            let width = Self.fittingWidth(of: Self.listCard("Esneme"), size: size)
            #expect(width <= Self.cardWidth, "the card asks for \(width) pt at \(size)")
        }

        /// The split shell's column card: the ring, the chip and the tally leave it inside the column.
        @Test(arguments: sizes)
        func columnRowFitsTheColumn(_ size: DynamicTypeSize) {
            let width = Self.fittingWidth(of: Self.columnRow("Esneme"), size: size)
            #expect(width <= Self.cardWidth, "the card asks for \(width) pt at \(size)")
        }

        private static func height(of view: some View, size: DynamicTypeSize) -> CGFloat {
            let sized =
                view
                .frame(width: cardWidth)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, locale)
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: cardWidth, height: 4000)).height
        }

        /// The width the view takes when it is offered the card's width: more means it overflows.
        private static func fittingWidth(of view: some View, size: DynamicTypeSize) -> CGFloat {
            let sized =
                view
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, locale)
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: cardWidth, height: 4000)).width
        }
    }
#endif
