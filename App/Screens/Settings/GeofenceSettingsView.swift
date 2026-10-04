#if os(iOS)
    import SwiftUI

    struct GeofenceSettingsView: View {
        @Environment(GeofenceService.self) private var geofences
        var body: some View {
            Section("Konuma girince") {
                Text("Konum hedefleri için Her zaman izni gerekir. Bölgeye girişte bugünün kaydı işaretlenir.")
                    .font(.caption).foregroundStyle(.secondary)
                if geofences.location.authorization == .always {
                    Text("Her zaman konum izni verildi.")
                } else {
                    Button("Her zaman konum izni ver") { geofences.requestAlwaysAccess() }
                }
                Text("Bildir seçeneği için Bildirimler ayarından bildirim izni ver.")
                    .font(.caption).foregroundStyle(.secondary)
                if geofences.targets.isEmpty { Text("Konum bağlantısı olan uygun hedef yok.") }
                ForEach(geofences.targets) { target in
                    Picker(
                        selection: Binding(
                            get: { geofences.mode(for: target) }, set: { geofences.setMode($0, for: target) })
                    ) {
                        Text("Kapalı").tag(GeofenceMode.off)
                        Text("Bildir").tag(GeofenceMode.notify)
                        Text("Otomatik işaretle").tag(GeofenceMode.automatic)
                    } label: {
                        Text(verbatim: target.goal.name)
                    }
                }
                if let error = geofences.errorText { Text(verbatim: error).foregroundStyle(.red) }
            }
            Section("İzlenen bölgeler") {
                if geofences.regions.isEmpty { Text("İzlenen bölge yok.") }
                ForEach(geofences.regions) { target in
                    VStack(alignment: .leading) {
                        Text(verbatim: target.goal.name)
                        Text(
                            "\(target.place.entity.name) · \(target.region.radius.formatted(.number.precision(.fractionLength(0)))) m"
                        ).font(.caption)
                        if let qualifier = target.place.entity.qualifier { Text(verbatim: qualifier).font(.caption) }
                    }
                }
                if geofences.overflowCount > 0 {
                    Text("20 bölge sınırı: \(geofences.overflowCount) hedef izlenmiyor.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
#endif
