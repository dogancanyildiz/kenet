import SwiftUI

enum AppLockCoverCopy {
    static let titleKey = "Kenet kilitli"
    static let promptKey = "Devam etmek için kimliğini doğrula."
    static let failureKey = "Kimlik doğrulanamadı. Tekrar dene."

    static func biometryButtonTitle(_ biometry: AppLockBiometry) -> String {
        switch biometry {
        case .faceID: return String(localized: "Face ID ile aç")
        case .touchID: return String(localized: "Touch ID ile aç")
        case .opticID: return String(localized: "Optic ID ile aç")
        case .none: return String(localized: "Parola ile aç")
        }
    }

    static func unlockButtonTitle(biometry: AppLockBiometry, authenticationFailed: Bool) -> String {
        if authenticationFailed {
            return String(localized: "Tekrar dene")
        }
        return biometryButtonTitle(biometry)
    }
}

struct KenetRingsBadge: View {
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 16
    var ringDiameter: CGFloat = 20
    var ringOffset: CGFloat = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.ink.accentSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.ink.accent.opacity(0.28), lineWidth: InkStroke.rule)
                )
            ZStack {
                Circle()
                    .strokeBorder(Color.ink.accent, lineWidth: 2.4)
                    .frame(width: ringDiameter, height: ringDiameter)
                    .offset(x: -ringOffset)
                Circle()
                    .strokeBorder(Color.ink.text, lineWidth: 2.4)
                    .frame(width: ringDiameter, height: ringDiameter)
                    .offset(x: ringOffset)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AppLockCover: View {
    let lock: AppLockService
    var allowsBackgroundAuthentication = false

    var body: some View {
        ZStack {
            Color.ink.paper
                .inkGlow()
                .ignoresSafeArea()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: InkSpacing.section) {
                        KenetRingsBadge()
                        VStack(spacing: 8) {
                            Text(LocalizedStringKey(AppLockCoverCopy.titleKey))
                                .font(.ink.dayName)
                                .foregroundStyle(Color.ink.text)
                            Text(
                                lock.authenticationFailed
                                    ? LocalizedStringKey(AppLockCoverCopy.failureKey)
                                    : LocalizedStringKey(AppLockCoverCopy.promptKey)
                            )
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .multilineTextAlignment(.center)
                        }
                        if lock.isForeground || allowsBackgroundAuthentication {
                            if lock.isAuthenticating {
                                InkProgress(kind: .indeterminate(label: "Kimlik doğrulanıyor…"))
                            } else {
                                Button(
                                    AppLockCoverCopy.unlockButtonTitle(
                                        biometry: lock.biometry,
                                        authenticationFailed: lock.authenticationFailed)
                                ) {
                                    Task { await lock.unlock() }
                                }
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
