#if os(macOS)
    import SwiftUI

    struct HotKeySettingsView: View {
        @Bindable var model: HotKeySettingsModel

        var body: some View {
            Form {
                Section("Hızlı giriş kısayolu") {
                    Text("Alana tıkla, tuş birleşimine bas ve kaydet.").foregroundStyle(.secondary)
                    HotKeyRecorder(
                        candidate: $model.candidate, onBegin: model.beginRecording, onEnd: model.endRecording
                    ).frame(height: 40)
                    HStack {
                        Button("Varsayılan kısayol") { model.candidate = .defaultShortcut }
                        Button("Kaydet") { model.save() }
                    }
                    Text("Geçerli kısayol: \(model.shortcut.display)").font(.caption)
                    if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .padding()
            .onDisappear { model.endRecording() }
        }
    }
#endif
