import SwiftUI

struct AppLockSettingsView: View {
    @Environment(AppLockService.self) private var lock
    @Environment(GeofenceService.self) private var geofences: GeofenceService?

    var body: some View {
        @Bindable var lock = lock
        Section {
            Toggle(
                "Uygulama kilidi",
                isOn: Binding(
                    get: { lock.isEnabled },
                    set: { enabled in
                        Task {
                            await lock.setEnabled(enabled)
                            geofences?.refreshMarkActionAvailability()
                        }
                    }
                )
            )
            .disabled(lock.isAuthenticating)
            .inkListRow()
            if lock.isEnabled {
                Picker("Şu kadar sonra kilitle", selection: $lock.delay) {
                    Text("Hemen").tag(AppLockDelay.immediately)
                    Text("1 dk").tag(AppLockDelay.oneMinute)
                    Text("5 dk").tag(AppLockDelay.fiveMinutes)
                    Text("15 dk").tag(AppLockDelay.fifteenMinutes)
                }
                .inkListRow()
            }
            if lock.authenticationFailed {
                Text("Kimlik doğrulanamadı. Tekrar dene.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                if !lock.isEnabled {
                    Button("Tekrar dene") {
                        Task {
                            await lock.setEnabled(true)
                            geofences?.refreshMarkActionAvailability()
                        }
                    }
                    .inkListRow()
                }
            }
            Text(
                "Kilitliyken Siri hedef adlarını listelemez; Kısayollar ve bildirimdeki İşaretle eylemi yazmaz."
            )
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
            .inkListRow()
        }
    }
}
