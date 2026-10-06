import Foundation
import VaultStore

enum RenameFailureCopy {
    /// Localized caption for a structured frontmatter-list rename failure.
    static func frontmatterList(key: String, reason: RenameListFailureReason, locale: Locale? = nil)
        -> String
    {
        let value: String.LocalizationValue =
            switch reason {
            case .unmatchedTokens:
                "Ön bilgi listesi güncellenemedi (\(key)): öğeler eşleştirilemedi."
            case .unexpected:
                "Ön bilgi listesi güncellenemedi (\(key))."
            }
        if let locale {
            return String(localized: value, locale: locale)
        }
        return String(localized: value)
    }
}
