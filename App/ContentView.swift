import SwiftUI

/// Starts the vault once and presents the platform's phase-one navigation.
struct ContentView: View {
    let store: IndexStore
    @Environment(IntentNavigation.self) private var intentNavigation
    @Environment(NotificationService.self) private var notifications
    @AppStorage(EntryPointsTipPreference.key) private var entryPointsTipDismissed = false
    /// Kept as an object so the search action is made once and still reaches the sheet.
    @State private var search = SearchPresentation()

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
                    .sheet(
                        isPresented: Binding(
                            get: { store.showsCloudMigration && store.isCloudMigrationAutomatic },
                            set: { store.showsCloudMigration = $0 })
                    ) {
                        NavigationStack { VaultCloudMigrationView(store: store) }
                    }
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
                    // iCloud sync under way, and what the day copy merge did (docs/screens.md, "Kasa eşitlenirken").
                    .safeAreaInset(edge: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            SyncStatusIndicator(status: store.syncStatus)
                            DayCopyMergeBand(sync: store.sync)
                        }
                    }
            }
        }
        .environment(\.openSearch, search.open)
        .environment(\.openSearchQuery, search.openQuery)
        .searchSheet(
            isPresented: $search.isPresented, store: store, initialQuery: search.initialQuery
        )
        #if os(macOS)
            .focusedSceneValue(\.openSearch, search.open)
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
        .onChange(of: intentNavigation.todayRequest) { search.isPresented = false }
        .onChange(of: notifications.navigationRequest?.id) { _, _ in search.isPresented = false }
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
            AdaptiveNavigation(store: store)
        #endif
    }

    private var entryPointsTip: LocalizedStringKey {
        LocalizedStringKey(EntryPointPlatform.tip(for: .current).key)
    }
}

/// Whether the global search sheet is up, and the one action that raises it (``ShellAction``):
/// the shell's magnifiers and, on the Mac, the menu bar's "Ara" and "Hızlı geçiş".
/// The Mac sidebar search field also opens the sheet with the typed query.
@MainActor @Observable
final class SearchPresentation {
    var isPresented = false
    /// Query handed to ``SearchView`` when the sheet opens (sidebar submit or empty for ⌘K).
    private(set) var initialQuery = ""
    @ObservationIgnored private(set) var open = ShellAction.nothing
    /// Stable callback for sidebar searchable submit (never recreated in a view body).
    @ObservationIgnored private(set) var openQuery: @MainActor @Sendable (String) -> Void = { _ in }

    init() {
        open = ShellAction { [weak self] in self?.openSheet() }
        openQuery = { @MainActor [weak self] query in self?.openSheet(query: query) }
    }

    func openSheet(query: String = "") {
        initialQuery = query
        isPresented = true
    }
}

/// "2 gün kopyası birleştirildi." and the like, after a day copy merge, until dismissed.
private struct DayCopyMergeBand: View {
    let sync: SyncState

    var body: some View {
        if let report = sync.mergeReport {
            InfoBand(
                kind: report.failed > 0 ? .warning : .info, verbatim: report.message,
                onDismiss: sync.dismissMergeReport
            )
            .background(Color.ink.paper)
            .accessibilityIdentifier("banner.dayCopyMerge")
        }
    }
}

#if DEBUG
    /// Copies the UI-test vault into the app sandbox so writes are permitted, then opens it.
    @MainActor
    private func openUITestVault(at path: String, store: IndexStore) async {
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let name = AppLaunchPolicy.uiTestVaultCopyName()
        let destination = caches.appendingPathComponent(name, isDirectory: true)
        let manager = FileManager.default
        // Copies named by earlier launches are not read again.
        let prefix = AppLaunchPolicy.uiTestVaultCopyDefaultName + "-"
        for old in (try? manager.contentsOfDirectory(atPath: caches.path)) ?? []
        where old.hasPrefix(prefix) && old != name {
            try? manager.removeItem(at: caches.appendingPathComponent(old, isDirectory: true))
        }
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
