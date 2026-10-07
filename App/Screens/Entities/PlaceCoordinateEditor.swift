import SwiftUI

/// Latitude and longitude of a place, written as the `coordinates` list the map and the
/// location suggestion read. The current position only fills the fields; nothing reaches
/// the file before "Kaydet". State rules live in ``PlaceCoordinateDraft``.
struct PlaceCoordinateEditor: View {
    let model: EntityDetailModel
    @Environment(LocationService.self) private var location: LocationService?
    @Environment(\.entityEditorDraft) private var sheetDraft
    @State private var draft: PlaceCoordinateDraft
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    private let draftID = "place.coordinates"

    init(model: EntityDetailModel) {
        self.model = model
        _draft = State(initialValue: PlaceCoordinateDraft(spellings: model.coordinateSpellings))
    }

    private var canLocate: Bool { location.map { $0.isEnabled && $0.authorization.canLocate } ?? false }
    private var unreadable: Bool { model.hasCoordinatesField && model.coordinate == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            if unreadable { unreadableValue }
            if model.coordinatesWritable {
                coordinateField("Enlem", text: $draft.latitude, identifier: "field.place.latitude")
                coordinateField("Boylam", text: $draft.longitude, identifier: "field.place.longitude")
                Button("Şu anki konumumu kullan") { useCurrentLocation() }
                    .buttonStyle(InkTextButtonStyle())
                    .disabled(!canLocate)
                    .inkAccessibilityIdentifier("button.place.coordinates.current")
                status
                HStack(spacing: InkSpacing.margin) {
                    Button("Kaydet") { save() }
                        .buttonStyle(InkTextButtonStyle())
                        .inkAccessibilityIdentifier("button.place.coordinates.save")
                    if model.hasCoordinatesField {
                        Button("Koordinatı kaldır", role: .destructive) { deleteConfirmation.request(.pending) }
                            .buttonStyle(InkDestructiveButtonStyle())
                    }
                }
            }
        }
        // Row default for a List row with several buttons; the word buttons carry ink styles.
        .buttonStyle(.borderless)
        .disabled(!model.canEdit)
        .onAppear { sheetDraft?.report(id: draftID, dirty: draft.isDirty) }
        .onChange(of: draft.isDirty) { sheetDraft?.report(id: draftID, dirty: draft.isDirty) }
        .onChange(of: location?.lastFix) { draft.fill(location?.currentCoordinate) }
        .destructiveConfirmationDialog(
            "Koordinatı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Koordinatı kaldır"
        ) { _ in
            Task {
                if await model.remove("coordinates") {
                    draft.removed()
                    sheetDraft?.clear(id: draftID)
                }
            }
        }
    }

    /// The stored value the map cannot use, shown as it stands in the file so the user sees
    /// what a save replaces (or, for a value the app cannot write, what to fix by hand).
    @ViewBuilder private var unreadableValue: some View {
        if model.coordinatesWritable {
            Text("Kayıtlı koordinat okunamıyor. Kaydet, aşağıdaki değerin yerine yenisini yazar.")
                .font(.ink.meta).foregroundStyle(.ink.secondaryText)
        } else {
            Text("Kayıtlı koordinat uygulamanın değiştiremediği bir biçimde. Dosyada elle düzelt.")
                .font(.ink.meta).foregroundStyle(.ink.secondaryText)
        }
        Text(verbatim: model.coordinatesSource)
            .font(.ink.content).foregroundStyle(.ink.secondaryText)
            .textSelection(.enabled)
    }

    @ViewBuilder private var status: some View {
        switch draft.status(canLocate: canLocate, fixFailed: location?.lastRequestFailed == true) {
        case .none: EmptyView()
        case .invalid:
            Text("Enlem -90 ile 90, boylam -180 ile 180 arasında bir sayı olmalı.")
                .font(.ink.meta).foregroundStyle(.ink.danger)
        case .saveFailed:
            Text(
                verbatim: model.errorText
                    ?? String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
            )
            .font(.ink.meta).foregroundStyle(.ink.danger)
        case .cannotLocate:
            Text("Konum izni ya da konum önerileri kapalı. Enlem ve boylamı elle yazabilirsin.")
                .font(.ink.meta).foregroundStyle(.ink.secondaryText)
        case .fixFailed:
            Text("Konum alınamadı. Yeniden dene ya da enlem ve boylamı elle yaz.")
                .font(.ink.meta).foregroundStyle(.ink.danger)
        case .locating:
            Text("Konum alınıyor…")
                .font(.ink.meta).foregroundStyle(.ink.secondaryText)
        }
    }

    /// The label stays above the field: once filled, the two numbers are told apart by it.
    private func coordinateField(_ label: LocalizedStringKey, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.ink.section).foregroundStyle(.ink.text)
            InkFilterField(label, text: text, identifier: identifier, showsClearButton: false)
                .onSubmit { save() }
                .autocorrectionDisabled()
                #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                #endif
        }
    }

    private func useCurrentLocation() {
        guard let location else { return }
        draft.requestFix()
        location.requestLocationIfNeeded(userInitiated: true)
        draft.fill(location.currentCoordinate)
    }

    private func save() {
        guard case .write(let latitude, let longitude) = draft.submit() else { return }
        let committed = (draft.latitude, draft.longitude)
        Task {
            let success = await model.saveCoordinate(latitude: latitude, longitude: longitude)
            draft.finishSave(latitude: committed.0, longitude: committed.1, success: success)
            sheetDraft?.report(id: draftID, dirty: draft.isDirty)
        }
    }
}
