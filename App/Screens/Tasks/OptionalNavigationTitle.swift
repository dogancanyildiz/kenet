import SwiftUI

/// Applies ``navigationTitle`` only when a title is provided (embedded boards keep the parent title).
struct OptionalNavigationTitle: ViewModifier {
    var title: LocalizedStringKey?

    init(_ title: LocalizedStringKey?) {
        self.title = title
    }

    func body(content: Content) -> some View {
        if let title {
            content.navigationTitle(title)
        } else {
            content
        }
    }
}
