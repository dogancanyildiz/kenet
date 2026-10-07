import Foundation
import SwiftUI

/// Path text shown in Settings → Vault. Production uses the real URL; tests may override.
enum VaultPathDisplay {
    /// Fictional path for snapshot references (no host username or temp directory).
    static let snapshotExample = "/Users/ada/Journal/Vault"

    static func text(for url: URL?, override: String? = nil) -> String? {
        if let override { return override }
        return url?.path
    }
}

private enum VaultPathDisplayOverrideKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// When set, Settings → Vault shows this path instead of `store.vaultURL.path`.
    var vaultPathDisplayOverride: String? {
        get { self[VaultPathDisplayOverrideKey.self] }
        set { self[VaultPathDisplayOverrideKey.self] = newValue }
    }
}
