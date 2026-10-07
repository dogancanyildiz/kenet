import SwiftUI

struct PeopleInsightsSettingsView: View {
    @AppStorage(PeopleInsightsPreference.key) private var days = PeopleInsightsPreference.defaultDays
    var body: some View {
        Section {
            SectionHeader("Kişi hatırlatmaları")
                .inkListRow()
            Stepper(value: threshold, in: 1...365) {
                LabeledContent("Görüşülmeyenler eşiği") {
                    Text("\(threshold.wrappedValue) gün")
                        .font(.ink.value)
                        .monospacedDigit()
                }
            }
            .inkListRow()
            Text("Bu süre, kişiler listesindeki hatırlatma bölümünü belirler.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        }
    }
    private var threshold: Binding<Int> {
        Binding(get: { PeopleInsightsPreference.normalized(days) }, set: { days = $0 })
    }
}
