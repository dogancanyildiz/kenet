#if os(macOS)
    import SwiftUI

    struct HotKeySettingsView: View {
        @Bindable var model: HotKeySettingsModel

        var body: some View {
            List {
                Section {
                    SectionHeader("Hızlı giriş kısayolu")
                        .inkListRow()
                    Text("Alana tıkla, tuş birleşimine bas ve kaydet.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                    HotKeyRecorder(
                        candidate: $model.candidate, onBegin: model.beginRecording, onEnd: model.endRecording
                    )
                    .frame(height: 40)
                    .inkListRow()
                    HStack(spacing: 16) {
                        Button("Varsayılan kısayol") { model.candidate = .defaultShortcut }
                            .buttonStyle(InkTextButtonStyle())
                        Button("Kaydet") { model.save() }
                            .buttonStyle(InkTextButtonStyle())
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                    .inkListRow()
                    Text("Geçerli kısayol: \(model.shortcut.display)")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                    if let error = model.errorText {
                        Text(verbatim: error)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.danger)
                            .inkListRow()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .inkPageNavigationTitle("Hızlı giriş")
            .inkPageColumn()
            .inkPage()
            .onDisappear { model.endRecording() }
        }
    }
#endif
