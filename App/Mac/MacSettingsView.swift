#if os(macOS)
    import SwiftUI

    /// The tabs of the Settings scene, in order (`docs/screens.md`). One table gives each tab its
    /// title, its icon and its page, so a tab cannot be tagged with another tab's content.
    enum MacSettingsTab: Hashable, CaseIterable {
        case quickEntry
        case privacy
        case notifications
        case calendarAndLocation
        case vault
        case diagnostics

        var title: LocalizedStringResource {
            switch self {
            case .quickEntry: "Hızlı giriş"
            case .privacy: "Gizlilik"
            case .notifications: "Bildirimler"
            case .calendarAndLocation: "Takvim ve Konum"
            case .vault: "Kasa"
            case .diagnostics: "Tanılama"
            }
        }

        var systemImage: String {
            switch self {
            case .quickEntry: "square.and.pencil"
            case .privacy: "lock"
            case .notifications: "bell"
            case .calendarAndLocation: "calendar"
            case .vault: "folder"
            case .diagnostics: "wrench.and.screwdriver"
            }
        }
    }

    /// The page of one Settings tab.
    struct MacSettingsPage: View {
        let tab: MacSettingsTab
        let store: IndexStore
        let shortcut: HotKeySettingsModel

        var body: some View {
            switch tab {
            case .quickEntry: HotKeySettingsView(model: shortcut)
            case .privacy: PrivacySettingsView()
            case .notifications: NotificationSettingsView()
            case .calendarAndLocation: CalendarAndLocationSettingsView()
            case .vault: MacVaultSettingsPage(store: store)
            case .diagnostics: DiagnosticsView(store: store)
            }
        }
    }

    /// The Kasa tab. A `NavigationStack` push adds a back item at the head of the window toolbar,
    /// and the Settings tab strip highlights its tab by position: the highlight slides one tab to
    /// the left. So a subpage replaces the tab's content instead, under a "Kasa" back button.
    struct MacVaultSettingsPage: View {
        let store: IndexStore
        /// The subpage the tab opens on; `nil` is the tab's root.
        @State var subpage: VaultSettingsSubpage?

        /// The import page exists only while an import is being prepared; without one the tab
        /// falls back to its root.
        static func shown(_ subpage: VaultSettingsSubpage?, hasImport: Bool) -> VaultSettingsSubpage? {
            subpage == .vaultImport && !hasImport ? nil : subpage
        }

        /// Preparation finished or was cancelled. Entity types stays open; it is not tied to the import.
        static func subpage(_ current: VaultSettingsSubpage?, whenImportEnds ended: Bool) -> VaultSettingsSubpage? {
            ended && current == .vaultImport ? nil : current
        }

        var body: some View {
            Group {
                switch Self.shown(subpage, hasImport: store.importModel != nil) {
                case nil:
                    VaultSettingsView(store: store, openSubpage: { subpage = $0 })
                case .entityTypes:
                    under { EntityTypesSettingsView(store: store) }
                case .vaultImport:
                    if let model = store.importModel {
                        under { VaultImportView(store: store, model: model, isSheet: false) }
                    }
                }
            }
            .onChange(of: store.importModel?.id) { _, id in
                // Preparation finished or was cancelled: leave the import page. Entity types
                // stays; only the import subpage was tied to that model.
                subpage = Self.subpage(subpage, whenImportEnds: id == nil)
            }
        }

        private func under<Page: View>(@ViewBuilder _ page: () -> Page) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    subpage = nil
                } label: {
                    Label("Kasa", systemImage: "chevron.left")
                }
                .buttonStyle(InkTextButtonStyle())
                .accessibilityLabel("Kasa'ya dön")
                .accessibilityIdentifier("button.settings.vault.back")
                // In line with the rows below: a plain Mac list insets its rows by 8 pt.
                .padding(.horizontal, InkSpacing.margin + 8)
                .padding(.top, 8)
                .inkPageColumn()
                page()
            }
            .inkPage()
        }
    }

    /// Mac Settings scene: five Settings tabs plus quick-entry shortcut.
    /// Tab order matches historical `dev` (Hızlı giriş first).
    struct MacSettingsView: View {
        let store: IndexStore
        @Bindable var shortcut: HotKeySettingsModel
        /// The tab the window opens on.
        @State var selectedTab: MacSettingsTab = .quickEntry

        var body: some View {
            TabView(selection: $selectedTab) {
                ForEach(MacSettingsTab.allCases, id: \.self) { tab in
                    MacSettingsPage(tab: tab, store: store, shortcut: shortcut)
                        .tabItem {
                            Label {
                                Text(tab.title)
                            } icon: {
                                Image(systemName: tab.systemImage)
                            }
                        }
                        .tag(tab)
                }
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
