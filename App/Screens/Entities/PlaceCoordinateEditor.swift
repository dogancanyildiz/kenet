import SwiftUI

/// Latitude and longitude of a place, written as the `coordinates` list the map and the
/// location suggestion read. The current position only fills the fields; nothing reaches
/// the file before "Kaydet".
struct PlaceCoordinateEditor: View {
    let model: EntityDetailModel
    @Environment(LocationService.self) private var location: LocationService?
    @Environment(\.entityEditorDraft) private var draft
    @State private var latitude: String
    @State private var longitude: String
    @State private var savedLatitude: String
    @State private var savedLongitude: String
    @State private var invalid = false
    @State private var saveFailed = false
    @State private var awaitingFix = false
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    private let draftID = "place.coordinates"

    init(model: EntityDetailModel) {
        self.model = model
        let latitude = model.coordinate.map { PlaceCoordinateInput.text($0.latitude) } ?? ""
        let longitude = model.coordinate.map { PlaceCoordinateInput.text($0.longitude) } ?? ""
        _latitude = State(initialValue: latitude)
        _longitude = State(initialValue: longitude)
        _savedLatitude = State(initialValue: latitude)
        _savedLongitude = State(initialValue: longitude)
    }

    private var isDirty: Bool { latitude != savedLatitude || longitude != savedLongitude }
    private var canLocate: Bool { location.map { $0.isEnabled && $0.authorization.canLocate } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            if model.hasCoordinatesField && model.coordinate == nil {
                Text("Kayıtlı koordinat okunamıyor; yenisini kaydedince düzelir.")
                    .font(.ink.meta).foregroundStyle(.ink.secondaryText)
            }
            coordinateField("Enlem", text: $latitude, identifier: "field.place.latitude")
            coordinateField("Boylam", text: $longitude, identifier: "field.place.longitude")
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
        // Row default for a List row with several buttons; the word buttons carry ink styles.
        .buttonStyle(.borderless)
        .disabled(!model.canEdit)
        .onAppear { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: [latitude, longitude, savedLatitude, savedLongitude]) {
            draft?.report(id: draftID, dirty: isDirty)
        }
        .onChange(of: location?.lastFix) { fillIfAwaiting() }
        .destructiveConfirmationDialog(
            "Koordinatı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Koordinatı kaldır"
        ) { _ in
            Task {
                if await model.remove("coordinates") {
                    latitude = ""
                    longitude = ""
                    savedLatitude = ""
                    savedLongitude = ""
                    invalid = false
                    saveFailed = false
                    draft?.clear(id: draftID)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if invalid {
            Text("Enlem -90 ile 90, boylam -180 ile 180 arasında bir sayı olmalı.")
                .font(.ink.meta).foregroundStyle(.ink.danger)
        } else if saveFailed {
            Text(
                verbatim: model.errorText
                    ?? String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
            )
            .font(.ink.meta).foregroundStyle(.ink.danger)
        } else if !canLocate {
            Text("Konum izni ya da konum önerileri kapalı. Enlem ve boylamı elle yazabilirsin.")
                .font(.ink.meta).foregroundStyle(.ink.secondaryText)
        } else if awaitingFix, location?.lastRequestFailed == true {
            Text("Konum alınamadı. Yeniden dene ya da enlem ve boylamı elle yaz.")
                .font(.ink.meta).foregroundStyle(.ink.danger)
        } else if awaitingFix {
            Text("Konum alınıyor…")
                .font(.ink.meta).foregroundStyle(.ink.secondaryText)
        }
    }

    private func coordinateField(_ prompt: LocalizedStringKey, text: Binding<String>, identifier: String) -> some View {
        InkFilterField(prompt, text: text, identifier: identifier, showsClearButton: false)
            .onSubmit { save() }
            .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
            #endif
    }

    private func useCurrentLocation() {
        guard let location else { return }
        awaitingFix = true
        location.requestLocationIfNeeded(userInitiated: true)
        fillIfAwaiting()
    }

    private func fillIfAwaiting() {
        guard awaitingFix, let point = location?.currentCoordinate else { return }
        latitude = PlaceCoordinateInput.text(point.latitude)
        longitude = PlaceCoordinateInput.text(point.longitude)
        awaitingFix = false
        invalid = false
    }

    private func save() {
        guard let point = PlaceCoordinateInput.coordinate(latitude: latitude, longitude: longitude) else {
            invalid = true
            return
        }
        invalid = false
        let committed = (latitude, longitude)
        Task {
            let success = await model.saveCoordinate(point)
            saveFailed = !success
            var nextLatitude = savedLatitude
            var nextLongitude = savedLongitude
            EntityEditorSaveMark.commitIfSaved(committed.0, success: success, into: &nextLatitude)
            EntityEditorSaveMark.commitIfSaved(committed.1, success: success, into: &nextLongitude)
            savedLatitude = nextLatitude
            savedLongitude = nextLongitude
            draft?.report(id: draftID, dirty: isDirty)
        }
    }
}
