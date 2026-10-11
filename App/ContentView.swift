import SwiftUI

/// Starts the vault once and presents the platform's phase-one navigation.
struct ContentView: View {
    let store: IndexStore
    @Environment(IntentNavigation.self) private var intentNavigation
    @Environment(NotificationService.self) private var notifications
    @AppStorage(EntryPointsTipPreference.key) private var entryPointsTipDismissed = false
    @State private var searchPresented = false

    /// The hint is session chrome. `AppRootScreen` only chooses onboarding, the inaccessible
    /// vault, or the main shell; it does not present views.
    private var showsEntryPointsTip: Bool {
        root == .main && EntryPointsTipPreference.shouldPresent(dismissed: entryPointsTipDismissed)
    }

    private var root: AppRootScreen {
        AppRootScreen.resolve(
            requiresOnboarding: store.requiresOnboarding,
            isVaultInaccessible: store.isVaultInaccessible)
    }

    var body: some View {
        Group {
            switch root {
            case .onboarding:
                OnboardingView(store: store)
            case .vaultInaccessible:
                VaultInaccessibleView(store: store)
            case .main:
                mainScreen
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if showsEntryPointsTip {
                            InfoBand(
                                kind: .info, entryPointsTip,
                                onDismiss: {
                                    EntryPointsTipPreference.dismiss(in: .standard)
                                }
                            )
                            .background(Color.ink.paper)
                            .accessibilityIdentifier("banner.entryPoints")
                        }
                    }
            }
        }
        .environment(\.openSearch, { searchPresented = true })
        .sheet(isPresented: $searchPresented) {
            SearchView(store: store)
                .environment(\.openSearch, { searchPresented = true })
        }
        #if os(macOS)
            .focusedSceneValue(\.openSearch, { searchPresented = true })
        #endif
        .sheet(item: Binding(get: { store.importModel }, set: { store.importModel = $0 })) { model in
            NavigationStack { VaultImportView(store: store, model: model) }
                .frame(minWidth: 320, minHeight: 440)
        }
        .overlay(alignment: .top) {
            if !store.requiresOnboarding && !store.isVaultInaccessible && store.indexingFileCount != nil
                && store.isProcessing
            {
                VaultIndexingProgress(store: store)
                    .padding(InkSpacing.margin)
                    .frame(maxWidth: .infinity)
                    .background(Color.ink.surface)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.ink.rule)
                            .frame(height: 1)
                    }
            }
        }
        .onChange(of: intentNavigation.todayRequest) { searchPresented = false }
        .onChange(of: notifications.navigationRequest?.id) { _, _ in searchPresented = false }
        .task {
            #if DEBUG
                if let path = AppLaunchPolicy.uiTestVaultPath() {
                    await openUITestVault(at: path, store: store)
                    return
                }
            #endif
            await store.startAutomatically()
        }
    }

    @ViewBuilder private var mainScreen: some View {
        #if os(macOS)
            MacNavigation(store: store)
        #else
            PhoneNavigation(store: store)
        #endif
    }

    private var entryPointsTip: LocalizedStringKey {
        #if os(iOS)
            "Siri, Kısayollar ve Eylem düğmesiyle de yazabilirsin."
        #else
            "Siri, Kısayollar ve klavye kısayoluyla da yazabilirsin."
        #endif
    }
}

#if DEBUG
    /// Copies the UI-test vault into the app sandbox so writes are permitted, then opens it.
    @MainActor
    private func openUITestVault(at path: String, store: IndexStore) async {
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let destination = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UITestVault", isDirectory: true)
        let manager = FileManager.default
        try? manager.removeItem(at: destination)
        do {
            try manager.copyItem(at: source, to: destination)
            await store.select(destination)
        } catch {
            // Fall back to the given path (may be readable but not writable outside the container).
            await store.select(source)
        }
    }
#endif
