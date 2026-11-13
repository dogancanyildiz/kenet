import SwiftUI

/// A page's own loads answered: what it draws is its data, not the state before the first answer.
/// Each page that loads after the index goes idle reports here (`pageReady(_:)`);
/// several pages in one tree (a list column and its detail) are ready only together. Nil when no
/// reporting page is in the tree. Nothing in the app reads it: snapshot hosts wait for it before
/// they capture, and a preference draws nothing.
struct PageReadyKey: PreferenceKey {
    static let defaultValue: Bool? = nil
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        if let next = nextValue() { value = (value ?? true) && next }
    }
}

extension View {
    /// Reports whether this page's loads have answered (``PageReadyKey``).
    func pageReady(_ isReady: Bool) -> some View {
        preference(key: PageReadyKey.self, value: isReady)
    }
}
