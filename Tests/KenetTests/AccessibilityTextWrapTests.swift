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

        private static func height(of view: some View, size: DynamicTypeSize) -> CGFloat {
            let sized =
                view
                .frame(width: cardWidth)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: "tr_TR"))
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: cardWidth, height: 4000)).height
        }
    }
#endif
