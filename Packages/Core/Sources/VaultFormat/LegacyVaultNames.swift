/// Names that vaults written before 2026-11-13 use, as `vault-format.md` lists them under
/// "Eski adlar ve geçiş". Readers accept them until the vault is migrated; writers never produce them.
public enum LegacyVaultNames {
    /// The old day folder, read beside `VaultLayout.dayFolder`.
    public static let dayFolder = "journal"
    /// The old name of the free-text section heading, read as `DaySectionKind.diary`.
    public static let diaryHeading = "Journal"
    /// The old `type` value of a day file. Day identity is the path, so the value stays reserved.
    public static let dayType = "journal"
}
