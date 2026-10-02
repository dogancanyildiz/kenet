import SwiftUI
import VaultFormat

/// Phase 0 placeholder: the app has nothing to show until the index and screens arrive.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Henüz görünür bir şey yok.")
                .font(.title3)
            Text("Kasa formatı sürümü: \(VaultFormatVersion.current)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
