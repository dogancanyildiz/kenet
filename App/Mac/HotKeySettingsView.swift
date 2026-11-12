#if os(macOS)
    import SwiftUI

    struct HotKeySettingsView: View {
        @Bindable var model: HotKeySettingsModel
        @Environment(\.locale) private var locale

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
                        candidate: $model.candidate, locale: locale,
                        onBegin: model.beginRecording,
                        onEnd: { model.endRecording(locale: locale) }
                    )
                    .frame(height: 40)
                    .inkListRow()
                    HStack(spacing: 16) {
                        Button("Varsayılan kısayol") { model.candidate = .defaultShortcut }
                            .buttonStyle(InkTextButtonStyle())
                        Button("Kaydet") { model.save(locale: locale) }
                            .buttonStyle(InkTextButtonStyle())
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderless)
                    .inkListRow()
                    Text(
                        verbatim: PresentationLocalization.string(
                            localized: "Geçerli kısayol: \(model.shortcut.display(locale: locale))",
                            locale: locale)
                    )
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
                EntryPointSections()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .inkPageNavigationTitle("Hızlı giriş")
            .inkPageScrollColumn()
            .inkPage()
            .onDisappear { model.endRecording(locale: locale) }
        }
    }
#endif
