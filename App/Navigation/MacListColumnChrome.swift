import SwiftUI

enum MacListColumnChrome {
    /// A Mac list insets its rows by this much; a manşet above the list lines up with them.
    static let rowInset: CGFloat = 8
    /// ``InkPageTitle`` starts 4 pt above an ``InkPageTitleRow`` (the first row of a list);
    /// a column whose manşet is not a list row adds the difference.
    static let titleTopInset: CGFloat = 4
    /// Extra room a Mac list leaves between two rows beyond their own insets (measured).
    static let rowGap: CGFloat = 4
}

extension View {
    /// Puts a stack manşet where the list columns (Görevler, Hedefler) draw theirs.
    func macListColumnTitle() -> some View {
        padding(.leading, MacListColumnChrome.rowInset)
            .padding(.top, MacListColumnChrome.titleTopInset)
    }
}
