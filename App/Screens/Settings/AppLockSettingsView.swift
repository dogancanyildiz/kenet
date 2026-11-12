import SwiftUI

struct AppLockSettingsView: View {
    @Environment(AppLockService.self) private var lock
    @Environment(GeofenceService.self) private var geofences: GeofenceService?

    var body: some View {
        @Bindable var lock = lock
        Section {
            SectionHeader("Kilit")
                .inkListRow()
            InkCard(padded: false) {
                VStack(alignment: .leading, spacing: 0) {
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
                    .frame(minHeight: InkButtonChrome.minimumHeight)
                    .padding(.horizontal, InkSpacing.cardPadding)

                    if lock.isEnabled {
                        InkCardDivider()
                        InkLabeledMenu(
                            "Şu kadar sonra kilitle", selection: $lock.delay,
                            options: [
                                InkMenuOption("Hemen", value: AppLockDelay.immediately),
                                InkMenuOption("1 dk", value: AppLockDelay.oneMinute),
                                InkMenuOption("5 dk", value: AppLockDelay.fiveMinutes),
                                InkMenuOption("15 dk", value: AppLockDelay.fifteenMinutes),
                            ], identifier: "menu.settings.lockDelay"
                        )
                        .frame(minHeight: InkButtonChrome.minimumHeight)
                        .padding(.horizontal, InkSpacing.cardPadding)
                    }
                }
            }
            .inkListRow()

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
