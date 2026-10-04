import SwiftUI

struct AppLockCover: View {
    let lock: AppLockService
    var allowsBackgroundAuthentication = false

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.largeTitle).accessibilityHidden(true)
                Text("Günlük kilitli").font(.title2)
                if lock.isForeground || allowsBackgroundAuthentication {
                    if lock.isAuthenticating {
                        ProgressView("Kimlik doğrulanıyor…")
                    } else {
                        if lock.authenticationFailed {
                            Text("Kimlik doğrulanamadı. Tekrar dene.")
                        }
                        Button("Tekrar dene") { Task { await lock.unlock() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
        }
    }
}

extension View {
    func appLockShield(_ lock: AppLockService) -> some View {
        self.disabled(lock.shouldCover)
            .accessibilityHidden(lock.shouldCover)
            .background(AppLockWindowShield(lock: lock))
    }
}
