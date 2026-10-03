import SwiftUI

/// Search stays reachable while its results screen is being built.
struct SearchButton: View {
    @State private var isPresented = false

    var body: some View {
        Button("Ara", systemImage: "magnifyingglass") { isPresented = true }
            .labelStyle(.iconOnly)
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    ContentUnavailableView("Arama sonraki sürümde", systemImage: "magnifyingglass")
                        .navigationTitle("Ara")
                        .toolbar {
                            Button("Kapat") { isPresented = false }
                        }
                }
                .frame(minWidth: 300, minHeight: 250)
            }
    }
}
