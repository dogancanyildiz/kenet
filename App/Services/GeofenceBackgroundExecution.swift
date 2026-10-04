#if os(iOS)
    import UIKit

    /// Keeps the file-first operation alive beyond the region callback's initial wake window.
    @MainActor
    final class GeofenceBackgroundExecution {
        private var identifier = UIBackgroundTaskIdentifier.invalid
        init() {
            identifier = UIApplication.shared.beginBackgroundTask(withName: "Geofence goal") { [weak self] in
                Task { @MainActor [weak self] in self?.end() }
            }
        }
        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
#endif
