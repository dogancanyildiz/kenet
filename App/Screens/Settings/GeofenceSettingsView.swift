#if os(iOS)
    import SwiftUI

    struct GeofenceSettingsView: View {
        @Environment(GeofenceService.self) private var geofences
        var body: some View {
            Section {
                SectionHeader("Konuma girince")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if geofences.location.authorization == .always {
                            Text("Her zaman konum izni verildi.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.text)
                                .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                                .padding(.horizontal, InkSpacing.cardPadding)
                        } else {
                            Button("Her zaman konum izni ver") { geofences.requestAlwaysAccess() }
                                .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        if geofences.targets.isEmpty {
                            InkCardDivider()
                            Text("Konum bağlantısı olan uygun hedef yok.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        ForEach(geofences.targets) { target in
                            InkCardDivider()
                            // Three choices: tabs, under the goal they belong to. The same three words
                            // repeat per goal, so each tab is read as "goal name, mode".
                            VStack(alignment: .leading, spacing: 6) {
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
                                    ], accessibilityLabelPrefix: target.goal.name)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .inkListRow()
                Text("Konum hedefleri için Her zaman izni gerekir. Bölgeye girişte bugünün kaydı işaretlenir.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                Text("Bildir seçeneği için Bildirimler ayarından bildirim izni ver.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
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
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if geofences.regions.isEmpty {
                            Text("İzlenen bölge yok.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        ForEach(Array(geofences.regions.enumerated()), id: \.element.id) { index, target in
                            if index > 0 { InkCardDivider() }
                            VStack(alignment: .leading, spacing: 2) {
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .inkListRow()
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
