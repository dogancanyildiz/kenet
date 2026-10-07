#if os(macOS)
    import Foundation
    import Observation

    @MainActor @Observable
    final class QuickEntryWindowModel {
        let entry: QuickEntryModel
        private(set) var isPresented = false
        private(set) var focusRequest = UUID()

        init(store: IndexStore) { entry = QuickEntryModel(store: store) }

        var statusText: String? {
            if entry.store.vaultURL == nil {
                return String(localized: "Kasa açık değil. Uygulamadan kasayı aç.")
            }
            if entry.store.isProcessing { return String(localized: "Kasa hazırlanıyor…") }
            if !entry.store.canAddEvent {
                return String(localized: "Kasa kullanılamıyor. Uygulamadan kasayı kontrol et.")
            }
            return nil
        }

        func open() {
            isPresented = true
            focusRequest = UUID()
        }

        /// A dismissed window keeps its draft and mention choices for the next opening.
        func close() { isPresented = false }
    }
#endif
