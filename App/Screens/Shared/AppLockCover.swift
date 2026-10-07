import SwiftUI

struct AppLockCover: View {
    let lock: AppLockService
    var allowsBackgroundAuthentication = false

    var body: some View {
        ZStack {
            Color.ink.paper.ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Günlük kilitli")
                            .font(.ink.byline)
                            .foregroundStyle(Color.ink.secondaryText)
                        if lock.isForeground || allowsBackgroundAuthentication {
                            if lock.isAuthenticating {
                                InkProgress(kind: .indeterminate(label: "Kimlik doğrulanıyor…"))
                            } else {
                                if lock.authenticationFailed {
                                    Text("Kimlik doğrulanamadı. Tekrar dene.")
                                        .font(.ink.meta)
                                        .foregroundStyle(Color.ink.secondaryText)
                                }
                                Button("Tekrar dene") { Task { await lock.unlock() } }
                                    .buttonStyle(InkPrimaryButtonStyle())
                            }
                        }
                    }
                    .padding(InkSpacing.margin)
                    .frame(
                        maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    func appLockShield(_ lock: AppLockService) -> some View {
        self.disabled(lock.shouldCover)
            .accessibilityHidden(lock.shouldCover)
            .background(AppLockWindowShield(lock: lock))
    }
}
