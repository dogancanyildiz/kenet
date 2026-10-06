import Foundation

/// Which top-level surface ContentView should present for the current vault session.
enum AppRootScreen: Equatable {
    case onboarding
    case vaultInaccessible
    case main

    static func resolve(requiresOnboarding: Bool, isVaultInaccessible: Bool) -> AppRootScreen {
        if requiresOnboarding { return .onboarding }
        if isVaultInaccessible { return .vaultInaccessible }
        return .main
    }
}
