import SwiftUI

private struct OpenSearchKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var openSearch: @MainActor @Sendable () -> Void {
        get { self[OpenSearchKey.self] }
        set { self[OpenSearchKey.self] = newValue }
    }
}

struct SearchButton: View {
    @Environment(\.openSearch) private var openSearch

    var body: some View {
        Button("Ara", systemImage: "magnifyingglass", action: openSearch)
            .labelStyle(.iconOnly)
    }
}

#if os(macOS)
    struct SearchNavigationKey: FocusedValueKey {
        typealias Value = () -> Void
    }

    extension FocusedValues {
        var openSearch: (() -> Void)? {
            get { self[SearchNavigationKey.self] }
            set { self[SearchNavigationKey.self] = newValue }
        }
    }
#endif
