#if os(iOS)
    import SwiftUI
    import Testing

    @testable import Kenet

    /// Rows leave their text room for a whole word on a 320 pt screen at every text size: a row
    /// whose text is one longer word is as tall as a row with one letter. Beside a scaled mark
    /// column (~137 pt at AX5) the word broke mid-word ("Kit / ap / no / tu").
    @MainActor @Suite
    struct AccessibilityTextWrapTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5,
        ]
        /// A 320 pt screen less the page margins.
        static let cardWidth: CGFloat = 320 - 2 * InkSpacing.margin

        @Test(arguments: sizes)
        func taskRowKeepsAWordOnOneLine(_ size: DynamicTypeSize) {
            func row(_ title: String) -> some View {
                InkCard {
                    InkTaskRow(title: title, state: TaskBoxState(status: .todo, priority: nil))
                }
            }
            let word = Self.height(of: row("yürüyüşü"), size: size)
            let letter = Self.height(of: row("y"), size: size)
            #expect(word == letter, "the word wrapped at \(size)")
        }

        @Test(arguments: sizes)
        func pastDayScheduleCardKeepsAWordOnOneLine(_ size: DynamicTypeSize) {
            func card(_ title: String) -> some View {
                ScheduleEntryCard(
                    isSelected: false, hairline: 1, meta: "Olay", spokenLabel: title, spokenValue: "",
                    onTap: {}, onEdit: {}, onDelete: {},
                    leading: {
                        Image(systemName: "pencil").frame(width: 32, height: 32)
                    },
                    title: {
                        Text(verbatim: title).font(.ink.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    },
                    extra: { EmptyView() })
            }
            let word = Self.height(of: card("Çınaraltı"), size: size)
            let letter = Self.height(of: card("Ç"), size: size)
            #expect(word == letter, "the word wrapped at \(size)")
        }

        /// The card padding scales up to xxxL and stops at its ceiling at accessibility sizes.
        @Test func cardPaddingStopsAtItsCeilingAtAccessibilitySizes() {
            #expect(InkSpacing.cardPadding(scaled: 21.6, dynamicTypeSize: .xxxLarge) == 21.6)
            #expect(InkSpacing.cardPadding(scaled: 49, dynamicTypeSize: .xxxLarge) == 49)
            #expect(
                InkSpacing.cardPadding(scaled: 49, dynamicTypeSize: .accessibility5)
                    == InkSpacing.accessibilityCardPaddingCeiling)
            #expect(InkSpacing.cardPadding(scaled: 12, dynamicTypeSize: .accessibility1) == 12)
        }

        /// The two largest default sizes, which keep the time column on a 375 pt screen.
        nonisolated static let largeDefaultSizes: [DynamicTypeSize] = [.xxLarge, .xxxLarge]

        /// A past-day row on a 320 pt screen at xxL and xxxL: the time is above the card, so the
        /// card's text holds a word that broke beside the time column ("güncel- / lemesi").
        @Test(arguments: largeDefaultSizes)
        func pastDayRowKeepsAWordOnOneLineOnANarrowScreen(_ size: DynamicTypeSize) {
            let word = Self.height(of: Self.pastDayRow("güncellemesi"), size: size)
            let letter = Self.height(of: Self.pastDayRow("g"), size: size)
            #expect(word == letter, "the word wrapped at \(size)")
        }

        /// The same row on a 375 pt screen keeps the time beside the card: it is as tall as its card
        /// alone in the width the column leaves. At L it does so on a 320 pt screen too.
        @Test(arguments: [(DynamicTypeSize.xxLarge, 375.0), (.xxxLarge, 375.0), (.large, 320.0), (.xLarge, 320.0)])
        func pastDayRowKeepsItsTimeColumn(_ size: DynamicTypeSize, screenWidth: Double) {
            let rowWidth = screenWidth - 2 * InkSpacing.margin
            let column = Self.size(
                of: InkTimeColumn(text: "11:30", font: .ink.meta.weight(.semibold), minWidth: 52), size: size,
                width: nil
            ).width
            let row = Self.size(of: Self.pastDayRow("güncellemesi"), size: size, width: rowWidth).height
            let card = Self.size(
                of: Self.pastDayCard("güncellemesi"), size: size, width: rowWidth - column - 8
            ).height
            #expect(row == card, "the time left its column at \(size) on a \(Int(screenWidth)) pt screen")
        }

        /// A Today event with a 12-hour time on a 320 pt screen at xxL and xxxL: the time is above
        /// the text, which then holds the word.
        @Test(arguments: largeDefaultSizes)
        func eventRowKeepsAWordOnOneLineOnANarrowScreen(_ size: DynamicTypeSize) {
            func row(_ text: String) -> some View {
                InkCard {
                    InkEventRow(time: "11:30\u{202F}AM", segments: [InkLinkSegment(text: text, kind: .plain)])
                }
                .environment(\.locale, Locale(identifier: "en_US"))
            }
            let word = Self.height(of: row("değerlendirmesi"), size: size)
            let letter = Self.height(of: row("d"), size: size)
            #expect(word == letter, "the word wrapped at \(size)")
        }

        /// An event row in a card of a 375 pt screen keeps its time beside the text at every default
        /// size: one line of text makes a row one line high.
        @Test(arguments: [DynamicTypeSize.large, .xLarge, .xxLarge, .xxxLarge])
        func eventRowKeepsItsTimeColumnOnAWiderScreen(_ size: DynamicTypeSize) {
            let width = 375 - 2 * InkSpacing.margin
            let timed = Self.size(
                of: InkCard { InkEventRow(time: "11:30", segments: [InkLinkSegment(text: "Not", kind: .plain)]) },
                size: size,
                width: width
            ).height
            let untimed = Self.size(
                of: InkCard { InkEventRow(time: nil, segments: [InkLinkSegment(text: "Not", kind: .plain)]) },
                size: size,
                width: width
            ).height
            #expect(timed == untimed, "the time took a line of its own at \(size)")
        }

        /// Which sizes stack the time by width, and where the line is.
        @Test func timeStacksByWidthOnlyAtTheTwoLargestDefaultSizes() {
            let narrow = InkSpacing.narrowPageRowWidth
            for size in [DynamicTypeSize.xSmall, .large, .xLarge, .accessibility1, .accessibility5] {
                #expect(InkSpacing.timeStackingWidth(narrowWidth: narrow, dynamicTypeSize: size) == nil)
            }
            for size in Self.largeDefaultSizes {
                #expect(InkSpacing.timeStackingWidth(narrowWidth: narrow, dynamicTypeSize: size) == narrow)
            }
            let layout = InkTimeRowLayout(gap: 8, stacksBelowWidth: narrow)
            #expect(layout.stacks(width: 320 - 2 * InkSpacing.margin))
            #expect(!layout.stacks(width: 375 - 2 * InkSpacing.margin))
            #expect(!layout.stacks(width: nil))
            #expect(!InkTimeRowLayout(gap: 8, stacksBelowWidth: nil).stacks(width: 100))
        }

        private static func pastDayCard(_ title: String) -> some View {
            ScheduleEntryCard(
                isSelected: false, hairline: 1, meta: "Olay", spokenLabel: title, spokenValue: "",
                onTap: {}, onEdit: {}, onDelete: {},
                leading: {
                    Image(systemName: "pencil").frame(width: 32, height: 32)
                },
                title: {
                    Text(verbatim: title).font(.ink.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                },
                extra: { EmptyView() })
        }

        private static func pastDayRow(_ title: String) -> some View {
            ScheduleTimeRow(time: "11:30", isTimed: true) { pastDayCard(title) }
        }

        private static func height(of view: some View, size: DynamicTypeSize) -> CGFloat {
            Self.size(of: view, size: size, width: cardWidth).height
        }

        private static func size(of view: some View, size: DynamicTypeSize, width: CGFloat?) -> CGSize {
            let sized =
                view
                .frame(width: width)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: "tr_TR"))
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: width ?? 4000, height: 4000))
        }
    }
#endif
