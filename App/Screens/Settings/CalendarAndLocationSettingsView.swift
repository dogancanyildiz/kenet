import SwiftUI

/// Calendar permission plus location suggestion / geofence settings.
struct CalendarAndLocationSettingsView: View {
    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Takvim ve Konum")
            #endif
            CalendarSettingsView()
            LocationSettingsView()
        }
        .listStyle(.plain)
        .inkToggle()
        .inkPageNavigationTitle("Takvim ve Konum")
        .inkPageColumn()
        .inkPage()
    }
}
