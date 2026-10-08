#if os(macOS)
    import SwiftUI

    enum MacSettingsTab: Hashable {
        case quickEntry
        case privacy
        case notifications
        case calendarAndLocation
        case vault
        case diagnostics
    }

    /// Mac Settings scene: five Settings tabs plus quick-entry shortcut.
    /// Tab order matches historical `dev` (Hızlı giriş first).
    struct MacSettingsView: View {
        let store: IndexStore
        @Bindable var shortcut: HotKeySettingsModel
        @State private var selectedTab: MacSettingsTab = .quickEntry

        var body: some View {
            TabView(selection: $selectedTab) {
                HotKeySettingsView(model: shortcut)
                    .tabItem { Label("Hızlı giriş", systemImage: "square.and.pencil") }
                    .tag(MacSettingsTab.quickEntry)
                PrivacySettingsView()
                    .tabItem { Label("Gizlilik", systemImage: "lock") }
                    .tag(MacSettingsTab.privacy)
                NotificationSettingsView()
                    .tabItem { Label("Bildirimler", systemImage: "bell") }
                    .tag(MacSettingsTab.notifications)
                CalendarAndLocationSettingsView()
                    .tabItem { Label("Takvim ve Konum", systemImage: "calendar") }
                    .tag(MacSettingsTab.calendarAndLocation)
                NavigationStack {
                    VaultSettingsView(store: store)
                }
                .tabItem { Label("Kasa", systemImage: "folder") }
                .tag(MacSettingsTab.vault)
                DiagnosticsView(store: store)
                    .tabItem { Label("Tanılama", systemImage: "wrench.and.screwdriver") }
                    .tag(MacSettingsTab.diagnostics)
            }
            .toolbarBackground(Color.ink.paper, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .background(SettingsWindowConfigurator())
            .inkToggle()
            .inkPage()
            .frame(
                minWidth: InkSpacing.macSettingsMinWidth,
                minHeight: InkSpacing.macSettingsMinHeight)
        }
    }

    private struct SettingsWindowConfigurator: NSViewRepresentable {
        func makeNSView(context: Context) -> ConfigView { ConfigView() }
        func updateNSView(_ view: ConfigView, context: Context) { view.apply() }

        final class ConfigView: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                apply()
            }

            func apply() {
                guard let window else { return }
                window.backgroundColor = NSColor(Color.ink.paper)
                window.titlebarAppearsTransparent = true
            }
        }
    }
#endif
