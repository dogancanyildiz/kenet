/// Defines compatibility with the formatVersion stored in .app/vault.json.
public enum VaultFormatVersion {
    /// The vault format version this package reads and writes.
    public static let current = 1

    /// Returns whether the vault version is no newer than the supported version.
    public static func canWrite(vaultVersion: Int) -> Bool {
        vaultVersion <= current
    }
}
