#if os(macOS)
    import SwiftUI

    /// Mac Settings scene: five Settings tabs plus quick-entry shortcut.
    struct MacSettingsView: View {
        let store: IndexStore
        @Bindable var shortcut: HotKeySettingsModel

        var body: some View {
            TabView {
                PrivacySettingsView()
                    .tabItem { Label("Gizlilik", systemImage: "lock") }
                NotificationSettingsView()
                    .tabItem { Label("Bildirimler", systemImage: "bell") }
                CalendarAndLocationSettingsView()
                    .tabItem { Label("Takvim ve Konum", systemImage: "calendar") }
                VaultSettingsView(store: store)
                    .tabItem { Label("Kasa", systemImage: "folder") }
                DiagnosticsView(store: store)
                    .tabItem { Label("Tanılama", systemImage: "wrench.and.screwdriver") }
                HotKeySettingsView(model: shortcut)
                    .tabItem { Label("Hızlı giriş", systemImage: "square.and.pencil") }
            }
            .frame(
                minWidth: InkSpacing.macSettingsMinWidth,
                minHeight: InkSpacing.macSettingsMinHeight)
        }
    }
#endif
