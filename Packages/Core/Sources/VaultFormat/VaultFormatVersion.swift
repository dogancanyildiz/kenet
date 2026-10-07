import CoreFoundation
import Foundation

/// Defines compatibility with the formatVersion stored in .app/vault.json.
public enum VaultFormatVersion {
    /// The vault format version this package reads and writes.
    public static let current = 1

    /// Returns whether the vault version is no newer than the supported version.
    public static func canWrite(vaultVersion: Int) -> Bool {
        vaultVersion <= current
    }

    /// Reads `formatVersion` from `.app/vault.json` bytes.
    ///
    /// Missing key, non-integer, boolean-as-number, or unreadable JSON yields `nil` (not writable).
    public static func formatVersion(in data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = json["formatVersion"] as? NSNumber,
            CFGetTypeID(value) != CFBooleanGetTypeID(),
            value.doubleValue == Double(value.intValue),
            value.intValue >= 0
        else { return nil }
        return value.intValue
    }
}
