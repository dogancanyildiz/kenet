import Foundation

extension QuickEntryModel {
    var suggestedPlace: NearbyPlace? {
        guard !dismissedLocation, !awaitingResolution, store.canAddEvent,
            let coordinate = locationService?.currentCoordinate
        else { return nil }
        return NearbyPlaces.nearest(to: coordinate, among: store.nearbyPlaces)
    }

    func focusLocation() { locationService?.requestLocationIfNeeded() }
    func dismissLocation() { dismissedLocation = true }

    func selectLocation() {
        guard !isSubmitting, !isCreating, let place = suggestedPlace else { return }
        let separator = text.isEmpty || text.last?.isWhitespace == true ? "" : " "
        let start = text.utf8.count + separator.utf8.count + 1
        text += separator + "@" + place.entity.name
        composer.pin(place.entity, nameRange: start..<(start + place.entity.name.utf8.count))
        dismissedLocation = true
    }
}
