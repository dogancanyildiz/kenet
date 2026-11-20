import Testing

@testable import Kenet

/// The Tasks list at large text sizes: a project card keeps its name whole and a row's meta
/// line goes onto a second line instead of breaking its words.
@Suite
struct TasksListRowMetaTests {
    @Test func accessibilitySizesAlwaysWrap() {
        #expect(TasksListRowMeta.wraps(isAccessibilitySize: true, isCarriedOver: true, hasRecurrence: false))
        #expect(TasksListRowMeta.wraps(isAccessibilitySize: true, isCarriedOver: false, hasRecurrence: false))
    }

    @Test func carriedOverLineStaysOneLineBelowAccessibilitySizes() {
        #expect(!TasksListRowMeta.wraps(isAccessibilitySize: false, isCarriedOver: true, hasRecurrence: false))
        #expect(TasksListRowMeta.wraps(isAccessibilitySize: false, isCarriedOver: true, hasRecurrence: true))
        #expect(TasksListRowMeta.wraps(isAccessibilitySize: false, isCarriedOver: false, hasRecurrence: false))
    }

    @Test func oneRowNeedsItsIdealWidth() {
        #expect(TaskMetaLineLayout.fitsOnOneRow(idealWidth: 132, in: 132))
        #expect(TaskMetaLineLayout.fitsOnOneRow(idealWidth: 132.4, in: 132))
        #expect(!TaskMetaLineLayout.fitsOnOneRow(idealWidth: 150, in: 132))
    }
}

#if os(iOS)
    import SwiftUI
    import VaultFormat

    @MainActor @Suite
    struct TasksLargeTextTests {
        nonisolated static let sizes: [DynamicTypeSize] = [
            .large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5,
        ]
        /// A 320 pt screen less the page margins.
        static let cardWidth: CGFloat = 320 - 2 * InkSpacing.margin

        /// "performans" broke into "perfor- / mans" beside the color dot at AX5.
        @Test(arguments: sizes)
        func projectCardKeepsItsNameOnOneLine(_ size: DynamicTypeSize) {
            func card(_ name: String) -> some View {
                TaskProjectCard(
                    project: name, completed: 0, total: 1, width: size.isAccessibilitySize ? nil : 170)
            }
            let word = Self.height(of: card("performans"), size: size)
            let longWord = Self.height(of: card("dokumantasyon"), size: size)
            let letter = Self.height(of: card("p"), size: size)
            // A name that shrinks to fit is lower than the letter; one that wrapped would be taller.
            #expect(word <= letter, "the name wrapped at \(size)")
            #expect(longWord <= letter, "the long name wrapped at \(size)")
        }

        /// "No project · Sep 26 ↓" shared a short line out at xxxL and drew "No / proje / ct". The
        /// parts now flow: the row is at most one meta line taller than it is with room to spare.
        @Test(arguments: [DynamicTypeSize.large, .xxxLarge])
        func metaLineFlowsInsteadOfBreakingWords(_ size: DynamicTypeSize) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let row = try #require(
                try await context.store.allTasks().first {
                    $0.sourceText.contains("Hafta sonu dinlenme planı yap")
                })
            let day = CalendarDate("2026-09-20")!
            func view(width: CGFloat) -> some View {
                TasksListRow(
                    store: context.store, row: row, day: day, isOverdue: false, isBusy: false,
                    allowsReopening: true, namesMissingProject: true
                ) {}
                .environment(\.shellKind, .tabs)
                .frame(width: width)
            }
            let locale = Locale(identifier: "en_US")
            let narrow = Self.height(of: view(width: Self.cardWidth), size: size, locale: locale)
            let wide = Self.height(of: view(width: 700), size: size, width: 700, locale: locale)
            let line = Self.height(
                of: Text(verbatim: "Sep").font(.ink.meta).fixedSize(), size: size, locale: locale)
            #expect(narrow <= wide + line + 3, "the meta line broke a word at \(size): \(narrow) > \(wide) + \(line)")
        }

        private static func height(
            of view: some View, size: DynamicTypeSize, width: CGFloat = cardWidth,
            locale: Locale = Locale(identifier: "tr_TR")
        ) -> CGFloat {
            let sized =
                view
                .frame(width: width)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, locale)
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: width, height: 4000)).height
        }
    }
#endif
