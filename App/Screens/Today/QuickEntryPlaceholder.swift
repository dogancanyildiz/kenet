import SwiftUI

/// The fixed entry slot will gain its write action in the quick-entry change.
struct QuickEntryPlaceholder: View {
    var body: some View {
        HStack {
            TextField("Gününden bir an…", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Hızlı giriş")
            Button("Gönder", systemImage: "arrow.up.circle.fill") {}
                .labelStyle(.iconOnly)
        }
        .disabled(true)
        .accessibilityHint("Hızlı giriş sonraki sürümde")
        .padding()
        .background(.bar)
    }
}
