import Foundation
import VaultFormat
import VaultStore

enum DayEditError {
    static func message(for error: any Error) -> String {
        switch error {
        case VaultStoreError.staleTarget:
            String(localized: "Dosya dışarıdan değişti. Yeniden dene.")
        case VaultStoreError.indexUpdateFailed:
            String(localized: "Değişiklik kaydedildi, indeks güncellenemedi.")
        case EditError.sectionNotWritable, EditError.contentNotRepresentable:
            String(localized: "Bu metin bölüm yapısını değiştiriyor. Başlıkları ve kod çitlerini kontrol et.")
        default:
            String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
        }
    }
}
