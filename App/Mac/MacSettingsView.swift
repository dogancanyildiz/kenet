#if os(macOS)
    import SwiftUI

    /// Mac Settings scene: five Settings tabs plus quick-entry shortcut.
    /// Tab order matches historical `dev` (Hızlı giriş first).
    struct MacSettingsView: View {
        let store: IndexStore
        @Bindable var shortcut: HotKeySettingsModel

        var body: some View {
            TabView {
                NavigationStack {
                    HotKeySettingsView(model: shortcut)
                }
                .tabItem { Label("Hızlı giriş", systemImage: "square.and.pencil") }
                NavigationStack {
                    PrivacySettingsView()
                }
                .tabItem { Label("Gizlilik", systemImage: "lock") }
                NavigationStack {
                    NotificationSettingsView()
                }
                .tabItem { Label("Bildirimler", systemImage: "bell") }
                NavigationStack {
                    CalendarAndLocationSettingsView()
                }
                .tabItem { Label("Takvim ve Konum", systemImage: "calendar") }
                NavigationStack {
                    VaultSettingsView(store: store)
                }
                .tabItem { Label("Kasa", systemImage: "folder") }
                NavigationStack {
                    DiagnosticsView(store: store)
                }
                .tabItem { Label("Tanılama", systemImage: "wrench.and.screwdriver") }
            }
            .inkToggle()
            .frame(
                minWidth: InkSpacing.macSettingsMinWidth,
                minHeight: InkSpacing.macSettingsMinHeight)
        }
    }
#endif
