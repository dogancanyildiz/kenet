import Foundation
import VaultStore

enum EntryWriteError {
    static var savedWithoutIndex: String {
        String(localized: "Olay kaydedildi, indeks güncellenemedi.")
    }

    static func message(for error: Error) -> String {
        switch error {
        case VaultStoreError.indexUpdateFailed:
            savedWithoutIndex
        case VaultStoreError.staleTarget:
            String(localized: "Dosya değişti. Yeniden dene.")
        case VaultStoreError.readOnlyVault:
            String(localized: "Bu kasa uygulamanın daha yeni bir sürümüyle yazılmış. Yazmak için uygulamayı güncelle.")
        case VaultStoreError.reservedFolderCaseMismatch(let found, let expected):
            String(
                localized:
                    "'\(found)' klasörünün adı '\(expected)' olmalı. Obsidian'da ya da Dosyalar'da yeniden adlandır."
            )
        default:
            String(localized: "Olay kaydedilemedi. Kasayı kontrol edip yeniden dene.")
        }
    }
}
