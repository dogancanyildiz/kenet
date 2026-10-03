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
        default:
            String(localized: "Olay kaydedilemedi. Kasayı kontrol edip yeniden dene.")
        }
    }
}
