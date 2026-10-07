#if os(iOS)
    import SwiftUI

    struct GeofenceSettingsView: View {
        @Environment(GeofenceService.self) private var geofences
        var body: some View {
            Section {
                SectionHeader("Konuma girince")
                    .inkListRow()
                Text("Konum hedefleri için Her zaman izni gerekir. Bölgeye girişte bugünün kaydı işaretlenir.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                if geofences.location.authorization == .always {
                    Text("Her zaman konum izni verildi.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.text)
                        .inkListRow()
                } else {
                    Button("Her zaman konum izni ver") { geofences.requestAlwaysAccess() }
                        .inkListRow()
                }
                Text("Bildir seçeneği için Bildirimler ayarından bildirim izni ver.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                if geofences.targets.isEmpty {
                    Text("Konum bağlantısı olan uygun hedef yok.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                }
                ForEach(geofences.targets) { target in
                    // Three choices: tabs, under the goal they belong to.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: target.goal.name)
                            .font(.ink.content)
                            .foregroundStyle(Color.ink.text)
                        InkTabs(
                            selection: Binding(
                                get: { geofences.mode(for: target) },
                                set: { geofences.setMode($0, for: target) }),
                            items: [
                                InkTabItem("Kapalı", value: GeofenceMode.off),
                                InkTabItem("Bildir", value: GeofenceMode.notify),
                                InkTabItem("Otomatik işaretle", value: GeofenceMode.automatic),
                            ])
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text(verbatim: target.goal.name))
                    .inkListRow()
                }
                if let error = geofences.errorText {
                    Text(verbatim: error)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.danger)
                        .inkListRow()
                }
            }
            Section {
                SectionHeader("İzlenen bölgeler")
                    .inkListRow()
                if geofences.regions.isEmpty {
                    Text("İzlenen bölge yok.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                }
                ForEach(geofences.regions) { target in
                    VStack(alignment: .leading) {
                        Text(verbatim: target.goal.name)
                            .font(.ink.content)
                            .foregroundStyle(Color.ink.text)
                        Text(
                            "\(target.place.entity.name) · \(target.region.radius.formatted(.number.precision(.fractionLength(0)))) m"
                        )
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        if let qualifier = target.place.entity.qualifier {
                            Text(verbatim: qualifier)
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                        }
                    }
                    .inkListRow()
                }
                if geofences.overflowCount > 0 {
                    Text("20 bölge sınırı: \(geofences.overflowCount) hedef izlenmiyor.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .inkListRow()
                }
            }
        }
    }
#endif
