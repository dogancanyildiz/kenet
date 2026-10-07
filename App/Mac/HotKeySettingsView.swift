#if os(macOS)
    import SwiftUI

    struct HotKeySettingsView: View {
        @Bindable var model: HotKeySettingsModel

        var body: some View {
            Form {
                Section("Hızlı giriş kısayolu") {
                    Text("Alana tıkla, tuş birleşimine bas ve kaydet.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                    HotKeyRecorder(
                        candidate: $model.candidate, onBegin: model.beginRecording, onEnd: model.endRecording
                    ).frame(height: 40)
                    HStack {
                        Button("Varsayılan kısayol") { model.candidate = .defaultShortcut }
                        Button("Kaydet") { model.save() }
                    }
                    .buttonStyle(.borderless)
                    Text("Geçerli kısayol: \(model.shortcut.display)")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                    if let error = model.errorText {
                        Text(verbatim: error)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.danger)
                    }
                }
            }
            .formStyle(.grouped)
            .listRowBackground(Color.ink.surface)
            .padding()
            .inkPageColumn()
            .inkPage()
            .onDisappear { model.endRecording() }
        }
    }
#endif
