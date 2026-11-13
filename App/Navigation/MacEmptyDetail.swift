import SwiftUI

/// Detail column with nothing selected: the shared empty state (one italic line, no box),
/// stretched over the column so the shell's `.inkPage()` paper reaches every edge. Günlük,
/// Görevler (projects included), Hedefler and Kişiler / Konumlar use this.
///
/// On iOS the split shell has no window toolbar and an empty detail has no manşet, so the
/// column keeps the magnifier where a manşet row puts it (top trailing, utility icon). The Mac
/// window's toolbar already holds it.
struct MacEmptyDetail: View {
    let message: LocalizedStringKey
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif

    init(_ message: LocalizedStringKey) {
        self.message = message
    }

    var body: some View {
        EmptyState(message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
                .overlay(alignment: .topTrailing) { searchSlot }
            #endif
    }

    #if os(iOS)
        @ViewBuilder private var searchSlot: some View {
            if shellKind == .split {
                SearchButton()
                    .buttonStyle(InkHeaderButtonStyle())
                    .environment(\.isInkHeaderActionSlot, true)
                    .padding(.horizontal, InkSpacing.margin)
            }
        }
    #endif
}
