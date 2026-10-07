import SwiftUI

/// Calendar permission plus location suggestion / geofence settings.
struct CalendarAndLocationSettingsView: View {
    var body: some View {
        Form {
            InkPageTitleRow("Takvim ve Konum")
            CalendarSettingsView()
            LocationSettingsView()
        }
        .formStyle(.grouped)
        .listRowBackground(Color.ink.paper)
        .inkPageNavigationTitle("Takvim ve Konum")
        .inkPageColumn()
        .inkPage()
    }
}
