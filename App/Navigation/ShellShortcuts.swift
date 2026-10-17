#if os(iOS)
    import SwiftUI

    /// Hardware-keyboard commands live behind the shell, outside its layout and VoiceOver.
    /// iOS uses buttons rather than the Mac menu's focused-value bridge.
    struct ShellShortcutButtons: View {
        let navigation: ShellNavigationState
        let shell: ShellKind
        @Environment(\.openSearch) private var openSearch
        // Standalone hosted shells can omit the service; commands then stay disabled.
        @Environment(AppLockService.self) private var appLock: AppLockService?

        var body: some View {
            Group {
                Button("Ara", action: openSearch)
                    .keyboardShortcut(JournalShortcut.search.key, modifiers: JournalShortcut.search.modifiers)
                Button("Hızlı geçiş", action: openSearch)
                    .keyboardShortcut(
                        JournalShortcut.quickSwitch.key, modifiers: JournalShortcut.quickSwitch.modifiers)
                Button("Bugüne git") { navigation.goToToday(shell: shell) }
                    .keyboardShortcut(JournalShortcut.today.key, modifiers: JournalShortcut.today.modifiers)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
            .disabled(appLock?.shouldCover ?? true)
        }
    }
#endif
