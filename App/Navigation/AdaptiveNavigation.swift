#if os(iOS)
    import SwiftUI

    /// The iOS main shell, chosen by the scene's size classes alone (``ShellKind/resolve(horizontal:vertical:)``):
    /// the iPhone Duo inner screen gets the Mac shell's sidebar and columns, every other scene
    /// the tab bar. A change of size class (the Duo opened or closed) swaps the shell.
    ///
    /// The split shell's selection lives here, above the swap; the tab shell keeps its own
    /// state for now and does not read it.
    struct AdaptiveNavigation: View {
        let store: IndexStore
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @State private var navigation: ShellNavigationState

        init(store: IndexStore, navigation: ShellNavigationState = ShellNavigationState()) {
            self.store = store
            _navigation = State(initialValue: navigation)
        }

        var body: some View {
            switch ShellKind.resolve(horizontal: horizontalSizeClass, vertical: verticalSizeClass) {
            case .tabs:
                PhoneNavigation(store: store)
            case .split:
                SplitShell(store: store, navigation: navigation)
            }
        }
    }

    /// The split shell on iOS: `MacNavigation` and what the Mac gets from its menu bar and
    /// Settings window instead (the Settings sheet behind the Today manşet's gear, the accent).
    private struct SplitShell: View {
        let store: IndexStore
        let navigation: ShellNavigationState
        @Environment(IntentNavigation.self) private var intentNavigation
        @Environment(NotificationService.self) private var notifications
        @State private var showingSettings = false

        var body: some View {
            MacNavigation(store: store, navigation: navigation)
                .environment(\.openSettings, { showingSettings = true })
                // A Siri or notification route lands on the shell, not behind the sheet.
                .onChange(of: intentNavigation.todayRequest) { _, _ in showingSettings = false }
                .onChange(of: notifications.navigationRequest?.id) { _, _ in showingSettings = false }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        PhoneSettingsView(store: store)
                            .inkSheet(
                                "Ayarlar", closeIdentifier: "button.settings.close",
                                onClose: { showingSettings = false })
                    }
                    .inkToggle()
                }
                // After `.sheet` so the accent also reaches what the shell presents.
                .tint(Color.ink.accent)
        }
    }
#endif
