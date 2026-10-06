import SwiftUI

extension View {
    /// Page chrome: paper background and hidden list/scroll system fill.
    /// Screens adopt this in a later Stage 9 pass; defined here as the shared entry point.
    func inkPage() -> some View {
        self
            .background(Color.ink.paper.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}
