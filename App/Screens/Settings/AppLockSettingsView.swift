import SwiftUI

struct AppLockSettingsView: View {
    @Environment(AppLockService.self) private var lock

    var body: some View {
        @Bindable var lock = lock
        Section("Gizlilik") {
            Toggle(
                "Uygulama kilidi",
                isOn: Binding(
                    get: { lock.isEnabled },
                    set: { enabled in Task { await lock.setEnabled(enabled) } }
                )
            )
            .disabled(lock.isAuthenticating)
            if lock.isEnabled {
                Picker("Şu kadar sonra kilitle", selection: $lock.delay) {
                    Text("Hemen").tag(AppLockDelay.immediately)
                    Text("1 dk").tag(AppLockDelay.oneMinute)
                    Text("5 dk").tag(AppLockDelay.fiveMinutes)
                    Text("15 dk").tag(AppLockDelay.fifteenMinutes)
                }
            }
            if lock.authenticationFailed {
                Text("Kimlik doğrulanamadı. Tekrar dene.").foregroundStyle(.secondary)
                if !lock.isEnabled {
                    Button("Tekrar dene") { Task { await lock.setEnabled(true) } }
                }
            }
            Text("Siri ve Kısayollar kilitliyken de kayıt yazabilir. Bildirim önizlemelerini sistem ayarları belirler.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
