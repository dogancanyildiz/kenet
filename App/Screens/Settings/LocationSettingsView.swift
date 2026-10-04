import SwiftUI

#if os(iOS)
    import UIKit
#endif

struct LocationSettingsView: View {
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var location = location
        Section("Konum") {
            Toggle("Konum önerisi", isOn: $location.isEnabled)
            Text("Konum yalnız hızlı girişte tek seferlik alınır; günlüğe otomatik eklenmez.")
                .font(.caption).foregroundStyle(.secondary)
            switch location.authorization {
            case .notDetermined:
                Text("Konum izni henüz verilmedi.")
                Button("Konum önerileri için izin ver") { location.requestAccess() }
                    .disabled(location.isRequesting)
            case .authorized: Text("Konum erişimine izin verildi.")
            case .denied: Text("Konum erişimi reddedildi.")
            case .restricted: Text("Konum erişimi bu cihazda kısıtlanmış.")
            }
            Button("Sistem ayarlarını aç") {
                #if os(iOS)
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                #else
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
                    {
                        openURL(url)
                    }
                #endif
            }
        }
        .onAppear { location.refreshAuthorization() }
    }
}
