import SwiftUI

private struct OpenSettingsKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens the in-app Settings sheet. Set on phone navigation; absent on Mac (menu).
    var openSettings: (@MainActor @Sendable () -> Void)? {
        get { self[OpenSettingsKey.self] }
        set { self[OpenSettingsKey.self] = newValue }
    }
}
