import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

struct VaultCloudMigrationView: View {
    let store: IndexStore

    private var deviceName: String {
        #if os(macOS)
            Host.current().localizedName ?? "Mac"
        #else
            UIDevice.current.name
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeadline("Kasayı iCloud’a taşı?")
                Text("Kasan iCloud’a kopyalanır; bu cihazdaki dosyalar korunur. iPhone ve Mac aynı klasörü paylaşır.")
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.text)
                Text("Vazgeç’e dokunursan kasa bu cihazda kalır; sonra Ayarlar’dan taşıyabilirsin.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                if store.isMigratingCloud {
                    InkProgress(kind: .indeterminate(label: "Kasa iCloud’a kopyalanıyor…"))
                }
                if let error = store.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
            }
            .padding(InkSpacing.margin)
            .inkPageColumn()
        }
        .inkPage()
        .disabled(store.isMigratingCloud)
        .interactiveDismissDisabled()
        .inkSheet(
            "Kasayı iCloud’a taşı?", confirm: .move,
            isBusy: store.isMigratingCloud, isCancelEnabled: !store.isMigratingCloud,
            cancelIdentifier: "button.vaultCloudMigration.cancel",
            confirmIdentifier: "button.vaultCloudMigration.confirm",
            onCancel: { Task { await store.continueLocally() } },
            onConfirm: { Task { await store.migrateVaultToCloud(deviceName: deviceName) } })
    }
}
