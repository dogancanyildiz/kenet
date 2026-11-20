import SwiftUI
import Testing

@testable import Kenet

/// Icon rows of the manşet at accessibility text sizes (``InkStackedHeaderRows``).
@Suite
struct PageHeaderIconRowsTests {
    @Test func iconsThatFitShareOneRow() {
        #expect(InkStackedHeaderRows.resolve(widths: [60, 60, 60], available: 288) == [0..<3])
        // Exactly as wide as the row: three icons and two gaps.
        #expect(InkStackedHeaderRows.resolve(widths: [90, 90, 90], available: 278) == [0..<3])
    }

    @Test func anIconThatDoesNotFitStartsTheNextRow() {
        #expect(InkStackedHeaderRows.resolve(widths: [110, 110, 110], available: 288) == [0..<2, 2..<3])
        #expect(InkStackedHeaderRows.resolve(widths: [200, 200, 200], available: 288) == [0..<1, 1..<2, 2..<3])
        #expect(InkStackedHeaderRows.resolve(widths: [90, 90, 90], available: 277) == [0..<2, 2..<3])
    }

    @Test func anIconWiderThanTheRowKeepsARowOfItsOwn() {
        #expect(InkStackedHeaderRows.resolve(widths: [400], available: 288) == [0..<1])
        #expect(InkStackedHeaderRows.resolve(widths: [60, 400, 60], available: 288) == [0..<1, 1..<2, 2..<3])
    }

    @Test func noWidthOrNoIcons() {
        #expect(InkStackedHeaderRows.resolve(widths: [110, 110, 110], available: nil) == [0..<3])
        #expect(InkStackedHeaderRows.resolve(widths: [], available: 288).isEmpty)
    }
}

#if os(iOS)
    /// The künye keeps every line on a 320 pt screen at accessibility text sizes, also where its container
    /// offers less height than it needs. A list row did that at accessibility sizes and the künye
    /// was cut to one line ("16 açık · 5 d…", Görevler).
    @MainActor @Suite
    struct PageHeaderBylineWrapTests {
        /// The sizes where the manşet stacks. The smaller sizes keep the drawing they had.
        nonisolated static let sizes: [DynamicTypeSize] = [.accessibility1, .accessibility3, .accessibility5]
        /// A 320 pt screen less the page margins.
        static let width: CGFloat = 320 - 2 * InkSpacing.margin
        static let longByline = "20 Eylül 2026 Pazar · 16 açık · 5 devreden"

        @Test(arguments: sizes)
        func bylineKeepsItsLinesWhenOfferedLessHeight(_ size: DynamicTypeSize) {
            let header = InkPageHeader(verbatim: "Görevler", byline: Self.longByline) {
                InkHeaderAction("Sırala", systemImage: "line.3.horizontal.decrease") {}
                InkHeaderAction("Ara", systemImage: "magnifyingglass") {}
            }
            let roomy = Self.height(of: header, size: size, offered: 4000)
            let tight = Self.height(of: header, size: size, offered: 1)
            #expect(tight == roomy, "the künye lost lines at \(size)")
        }

        /// The styled künye of Görevler (bold count, warning part) wraps the same way.
        @Test(arguments: sizes)
        func styledBylineKeepsItsLinesWhenOfferedLessHeight(_ size: DynamicTypeSize) {
            let byline = Text("\(Text(verbatim: "16").fontWeight(.semibold)) açık · \(Text(verbatim: "5 devreden"))")
            let header = InkPageHeader(verbatim: "Görevler") {
                InkHeaderAction("Ara", systemImage: "magnifyingglass") {}
            }
            .byline(Text("\(byline) · \(Text(verbatim: Self.longByline))"))
            let roomy = Self.height(of: header, size: size, offered: 4000)
            let tight = Self.height(of: header, size: size, offered: 1)
            #expect(tight == roomy, "the künye lost lines at \(size)")
        }

        /// The künye wraps at accessibility sizes: a long one makes the manşet taller than a
        /// one-word one. (A cut künye is as tall as the short one.)
        @Test(arguments: sizes)
        func longBylineWraps(_ size: DynamicTypeSize) {
            func header(_ byline: String) -> some View {
                InkPageHeader(verbatim: "Görevler", byline: byline) {
                    InkHeaderAction("Ara", systemImage: "magnifyingglass") {}
                }
            }
            let long = Self.height(of: header(Self.longByline), size: size, offered: 1)
            let short = Self.height(of: header("16"), size: size, offered: 1)
            #expect(long > short, "the künye did not wrap at \(size)")
        }

        /// Three icons at the largest text size are wider than a 320 pt screen: the manşet stays
        /// as wide as the screen and the icons take a second row.
        @Test func threeIconsStayOnA320PointScreenAtTheLargestSize() {
            func header(icons: Int) -> some View {
                InkPageHeader(verbatim: "Görevler") {
                    ForEach(0..<icons, id: \.self) { _ in
                        InkHeaderAction("Ara", systemImage: "magnifyingglass") {}
                    }
                }
            }
            let two = Self.size(of: header(icons: 2), size: .accessibility5, offered: 4000)
            let three = Self.size(of: header(icons: 3), size: .accessibility5, offered: 4000)
            #expect(three.height > two.height, "the third icon did not take a second row")
            // At AX1 three icons fit one row.
            let twoSmall = Self.size(of: header(icons: 2), size: .accessibility1, offered: 4000)
            let threeSmall = Self.size(of: header(icons: 3), size: .accessibility1, offered: 4000)
            #expect(threeSmall.height == twoSmall.height)
        }

        /// A subpage's back item keeps the parent's name whole: beside two icons at the largest
        /// size it broke letter by letter ("G / ör / e / vl / er"). The icons go under it, so a
        /// long name is as tall as a short one (neither fits beside the icons at this size).
        @Test func backItemKeepsAWordOnOneLineAtTheLargestSize() {
            func header(back: String) -> some View {
                InkPageHeader(verbatim: "Deniz") {
                    InkHeaderAction("Düzenle", systemImage: "pencil") {}
                    InkHeaderAction("Ara", systemImage: "magnifyingglass") {}
                }
                .environment(\.inkHeaderBackTitle, Text(verbatim: back))
                .environment(\.shellKind, .tabs)
            }
            let word = Self.height(of: header(back: "Görevler"), size: .accessibility5, offered: 4000)
            let short = Self.height(of: header(back: "Gör"), size: .accessibility5, offered: 4000)
            #expect(word == short, "the back item wrapped inside a word")
        }

        /// The title wraps whole at accessibility sizes, also when offered less height.
        @Test(arguments: [DynamicTypeSize.accessibility3, .accessibility5])
        func titleKeepsItsLinesWhenOfferedLessHeight(_ size: DynamicTypeSize) {
            let header = InkPageHeader(verbatim: "Deniz Arıkan ile uzun bir başlık", byline: "Kişi") {
                InkHeaderAction("Ara", systemImage: "magnifyingglass") {}
            }
            let roomy = Self.height(of: header, size: size, offered: 4000)
            let tight = Self.height(of: header, size: size, offered: 1)
            #expect(tight == roomy, "the title lost lines at \(size)")
        }

        private static func height(of view: some View, size: DynamicTypeSize, offered: CGFloat) -> CGFloat {
            self.size(of: view, size: size, offered: offered).height
        }

        private static func size(of view: some View, size: DynamicTypeSize, offered: CGFloat) -> CGSize {
            let sized =
                view
                .frame(width: width)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: "tr_TR"))
            return UIHostingController(rootView: sized)
                .sizeThatFits(in: CGSize(width: width, height: offered))
        }
    }
#endif
