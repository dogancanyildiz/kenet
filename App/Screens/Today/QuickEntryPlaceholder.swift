import SwiftUI

struct QuickEntryBar: View {
    let store: IndexStore
    let isEnabled: Bool
    @State private var text = ""
    @State private var includesTime = true
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        isEnabled && store.canAddEvent && !text.allSatisfy(\.isWhitespace)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEnabled, let error = store.entryErrorText {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            HStack {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Button {
                        includesTime.toggle()
                    } label: {
                        if includesTime {
                            Text(context.date, format: .dateTime.hour().minute())
                                .monospacedDigit()
                        } else {
                            Image(systemName: "clock.badge.xmark")
                        }
                    }
                    .accessibilityLabel(includesTime ? Text("Saati kaldır") : Text("Şu anki saati ekle"))
                    .disabled(!isEnabled || store.isWriting)
                }
                TextField("Gününden bir an…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Hızlı giriş")
                    .focused($isFocused)
                    .disabled(!isEnabled)
                    .onSubmit { submit() }
                Button("Gönder", systemImage: "arrow.up.circle.fill") { submit() }
                    .labelStyle(.iconOnly)
                    .disabled(!canSubmit)
            }
        }
        .padding()
        .background(.bar)
    }

    private func submit() {
        guard canSubmit else { return }
        let submitted = text
        let time = includesTime ? LocalDay.clock() : nil
        isFocused = true
        Task { @MainActor in
            let saved = await store.addEvent(text: submitted, time: time)
            // Preserve anything typed while the file operation was in flight.
            if saved && text == submitted { text = "" }
            isFocused = true
        }
    }
}
