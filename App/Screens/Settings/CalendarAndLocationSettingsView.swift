import SwiftUI

/// Calendar permission plus location suggestion / geofence settings.
struct CalendarAndLocationSettingsView: View {
    var body: some View {
        Form {
            CalendarSettingsView()
            LocationSettingsView()
        }
        .formStyle(.grouped)
        .inkPage()
        .inkPageColumn()
    }
}
