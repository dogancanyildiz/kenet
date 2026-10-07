import Foundation

/// State of the coordinate editor, apart from the view: the typed pair, what the file holds,
/// the pending "current location" fill and which hint to show.
struct PlaceCoordinateDraft: Equatable {
    enum Status: Equatable {
        case none, invalid, saveFailed, cannotLocate, fixFailed, locating
    }

    /// What "Kaydet" does with the typed pair.
    enum Submission: Equatable {
        case invalid
        /// The file already holds this pair; nothing is written.
        case unchanged
        /// The spellings to write: an untouched field keeps the file's own digits.
        case write(latitude: String, longitude: String)
    }

    private(set) var latitudeText: String
    private(set) var longitudeText: String
    private(set) var savedLatitude: String
    private(set) var savedLongitude: String
    private(set) var hasStoredCoordinate: Bool
    private(set) var invalid = false
    private(set) var saveFailed = false
    private(set) var awaitingFix = false

    /// - Parameter spellings: the valid pair as the file spells it, or nil.
    init(spellings: [String]? = nil) {
        let pair = spellings?.count == 2 ? spellings : nil
        latitudeText = pair?[0] ?? ""
        longitudeText = pair?[1] ?? ""
        savedLatitude = latitudeText
        savedLongitude = longitudeText
        hasStoredCoordinate = pair != nil
    }

    /// Typing in a field: the user took over, so a fix that arrives later no longer fills it.
    var latitude: String {
        get { latitudeText }
        set {
            guard newValue != latitudeText else { return }
            latitudeText = newValue
            awaitingFix = false
        }
    }

    var longitude: String {
        get { longitudeText }
        set {
            guard newValue != longitudeText else { return }
            longitudeText = newValue
            awaitingFix = false
        }
    }

    var isDirty: Bool { latitudeText != savedLatitude || longitudeText != savedLongitude }

    mutating func requestFix() { awaitingFix = true }

    /// Fills both fields with the measured position, only while the user still waits for it.
    mutating func fill(_ point: PlaceCoordinate?) {
        guard awaitingFix, let point, point.isValid else { return }
        latitudeText = PlaceCoordinateInput.text(point.latitude)
        longitudeText = PlaceCoordinateInput.text(point.longitude)
        awaitingFix = false
        invalid = false
    }

    mutating func submit() -> Submission {
        guard PlaceCoordinateInput.coordinate(latitude: latitudeText, longitude: longitudeText) != nil,
            let latitude = PlaceCoordinateInput.spelling(latitudeText),
            let longitude = PlaceCoordinateInput.spelling(longitudeText)
        else {
            invalid = true
            return .invalid
        }
        invalid = false
        if hasStoredCoordinate && !isDirty {
            saveFailed = false
            return .unchanged
        }
        return .write(
            latitude: hasStoredCoordinate && latitudeText == savedLatitude ? savedLatitude : latitude,
            longitude: hasStoredCoordinate && longitudeText == savedLongitude ? savedLongitude : longitude)
    }

    /// Marks the texts that were sent as saved, only when the write succeeded.
    mutating func finishSave(latitude: String, longitude: String, success: Bool) {
        saveFailed = !success
        guard success else { return }
        savedLatitude = latitude
        savedLongitude = longitude
        hasStoredCoordinate = true
    }

    mutating func removed() {
        self = PlaceCoordinateDraft()
    }

    /// One hint at a time: what blocks the save first, then the location request.
    func status(canLocate: Bool, fixFailed: Bool) -> Status {
        if invalid { return .invalid }
        if saveFailed { return .saveFailed }
        if !canLocate { return .cannotLocate }
        if awaitingFix { return fixFailed ? .fixFailed : .locating }
        return .none
    }
}
