import SwiftUI

struct PeopleInsightsSettingsView: View {
    @AppStorage(PeopleInsightsPreference.key) private var days = PeopleInsightsPreference.defaultDays
    var body: some View {
        Section("Kişi hatırlatmaları") {
            Stepper(value: threshold, in: 1...365) {
                LabeledContent("Görüşülmeyenler eşiği") {
                    Text("\(threshold.wrappedValue) gün")
                        .font(.ink.value)
                        .monospacedDigit()
                }
            }
            Text("Bu süre, kişiler listesindeki hatırlatma bölümünü belirler.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
    }
    private var threshold: Binding<Int> {
        Binding(get: { PeopleInsightsPreference.normalized(days) }, set: { days = $0 })
    }
}
