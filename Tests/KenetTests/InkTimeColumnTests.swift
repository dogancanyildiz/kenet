import SwiftUI
import Testing

@testable import Kenet

/// The time column keeps its time on one line: in a row narrower than the time it stays one line
/// high instead of wrapping ("11:3" over "0").
@MainActor @Suite
struct InkTimeColumnTests {
    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5])
    func timeStaysOnOneLineWhenTheColumnIsTooNarrow(_ size: DynamicTypeSize) {
        for locale in ["tr_TR", "en_US"] {
            let time = EventTimeFormat.string(hour: 11, minute: 30, locale: Locale(identifier: locale))
            let narrow = Self.size(of: time, locale: locale, textSize: size, rowWidth: 20)
            let free = Self.size(of: time, locale: locale, textSize: size)
            #expect(narrow.height == free.height, "\(locale) wrapped at \(size)")
            #expect(free.width > 20)
        }
    }

    /// Every row of a list is as wide as the locale's widest time, so their contents line up.
    @Test func rowsOfOneListShareTheColumnWidth() {
        let locale = Locale(identifier: "en_US")
        let short = Self.size(
            of: EventTimeFormat.string(hour: 9, minute: 5, locale: locale), locale: "en_US", textSize: .xxxLarge)
        let long = Self.size(
            of: EventTimeFormat.string(hour: 23, minute: 30, locale: locale), locale: "en_US", textSize: .xxxLarge)
        #expect(short.width == long.width)
    }

    /// While the time fits, the column is exactly its minimum width (the fixed column it replaced).
    @Test func columnKeepsItsMinimumWidthWhileTheTimeFits() {
        let size = Self.size(of: "11:30", locale: "tr_TR", textSize: .large, minWidth: 120)
        #expect(size.width == 120)
    }

    private static func size(
        of time: String, locale: String, textSize: DynamicTypeSize, rowWidth: CGFloat? = nil,
        minWidth: CGFloat = 10
    ) -> CGSize {
        // A row of `rowWidth` offers the column that much; the row's height is the column's.
        let view = InkTimeColumn(text: time, minWidth: minWidth)
            .frame(width: rowWidth)
            .environment(\.locale, Locale(identifier: locale))
            .environment(\.dynamicTypeSize, textSize)
        let proposal = CGSize(width: 2000, height: 2000)
        #if os(macOS)
            return NSHostingController(rootView: view).sizeThatFits(in: proposal)
        #else
            return UIHostingController(rootView: view).sizeThatFits(in: proposal)
        #endif
    }
}
