import Foundation

/// Hex values for the Şafak palette (`docs/design.md` draft).
/// Asset catalog color sets must match these; ``PaletteContrastTests`` enforces that.
enum InkPalette {
    struct Variant: Equatable, Sendable {
        let light: UInt32
        let dark: UInt32
        let highContrastLight: UInt32
        let highContrastDark: UInt32
        /// Alpha 0…1 per appearance. Opaque tokens use `1`.
        let lightAlpha: Double
        let darkAlpha: Double
        let highContrastLightAlpha: Double
        let highContrastDarkAlpha: Double

        init(
            light: UInt32, dark: UInt32,
            highContrastLight: UInt32, highContrastDark: UInt32,
            lightAlpha: Double = 1, darkAlpha: Double = 1,
            highContrastLightAlpha: Double = 1, highContrastDarkAlpha: Double = 1
        ) {
            self.light = light
            self.dark = dark
            self.highContrastLight = highContrastLight
            self.highContrastDark = highContrastDark
            self.lightAlpha = lightAlpha
            self.darkAlpha = darkAlpha
            self.highContrastLightAlpha = highContrastLightAlpha
            self.highContrastDarkAlpha = highContrastDarkAlpha
        }

        func hex(for appearance: Appearance) -> UInt32 {
            switch appearance {
            case .light: light
            case .dark: dark
            case .highContrastLight: highContrastLight
            case .highContrastDark: highContrastDark
            }
        }

        func alpha(for appearance: Appearance) -> Double {
            switch appearance {
            case .light: lightAlpha
            case .dark: darkAlpha
            case .highContrastLight: highContrastLightAlpha
            case .highContrastDark: highContrastDarkAlpha
            }
        }
    }

    enum Appearance: String, CaseIterable, Sendable {
        case light
        case dark
        case highContrastLight
        case highContrastDark
    }

    enum Token: String, CaseIterable, Sendable {
        case paper
        case elevated
        case surface
        case well
        case rule
        case line
        case text
        case secondaryText
        case tertiaryText
        case accent
        case onAccent
        case accentSoft
        case warning
        case danger
        case control
        case person
        case place

        var assetName: String {
            switch self {
            case .paper: "InkPaper"
            case .elevated: "InkElevated"
            case .surface: "InkSurface"
            case .well: "InkWell"
            case .rule: "InkRule"
            case .line: "InkLine"
            case .text: "InkText"
            case .secondaryText: "InkSecondaryText"
            case .tertiaryText: "InkTertiaryText"
            case .accent: "InkAccent"
            case .onAccent: "InkOnAccent"
            case .accentSoft: "InkAccentSoft"
            case .warning: "InkWarning"
            case .danger: "InkDanger"
            case .control: "InkControl"
            case .person: "InkPerson"
            case .place: "InkPlace"
            }
        }

        var variant: Variant {
            switch self {
            case .paper:
                // bg
                Variant(
                    light: 0xF3_F3_F6, dark: 0x0E_0F_11,
                    highContrastLight: 0xF3_F3_F6, highContrastDark: 0x08_09_0A)
            case .elevated:
                // bgElev
                Variant(
                    light: 0xFA_FA_FC, dark: 0x14_15_18,
                    highContrastLight: 0xFF_FF_FF, highContrastDark: 0x0E_0F_11)
            case .surface:
                // card
                Variant(
                    light: 0xFF_FF_FF, dark: 0x1A_1B_1F,
                    highContrastLight: 0xFF_FF_FF, highContrastDark: 0x1A_1B_1F)
            case .well:
                // card2
                Variant(
                    light: 0xF1_F1_F5, dark: 0x21_22_28,
                    highContrastLight: 0xF1_F1_F5, highContrastDark: 0x21_22_28)
            case .rule:
                // hair: black/white at 7% (16% HC)
                Variant(
                    light: 0x00_00_00, dark: 0xFF_FF_FF,
                    highContrastLight: 0x00_00_00, highContrastDark: 0xFF_FF_FF,
                    lightAlpha: 0.07, darkAlpha: 0.07,
                    highContrastLightAlpha: 0.16, highContrastDarkAlpha: 0.16)
            case .line:
                // line: black/white at 12% (24% HC)
                Variant(
                    light: 0x00_00_00, dark: 0xFF_FF_FF,
                    highContrastLight: 0x00_00_00, highContrastDark: 0xFF_FF_FF,
                    lightAlpha: 0.12, darkAlpha: 0.12,
                    highContrastLightAlpha: 0.24, highContrastDarkAlpha: 0.24)
            case .text:
                Variant(
                    light: 0x15_16_1A, dark: 0xF2_F2_F4,
                    highContrastLight: 0x05_05_07, highContrastDark: 0xFF_FF_FF)
            case .secondaryText:
                Variant(
                    light: 0x53_56_5E, dark: 0xA7_AA_B2,
                    highContrastLight: 0x3A_3D_44, highContrastDark: 0xCD_D0_D6)
            case .tertiaryText:
                // Light darkened so ≥ 4.5:1 on accentSoft (`#5E6168`).
                Variant(
                    light: 0x5E_61_68, dark: 0x8E_91_99,
                    highContrastLight: 0x4A_4D_55, highContrastDark: 0xB4_B7_BE)
            case .accent:
                Variant(
                    light: 0x7A_2C_6E, dark: 0xD0_8B_C4,
                    highContrastLight: 0x5E_1F_55, highContrastDark: 0xE8_BC_E0)
            case .onAccent:
                Variant(
                    light: 0xFF_FF_FF, dark: 0x1B_0E_18,
                    highContrastLight: 0xFF_FF_FF, highContrastDark: 0x12_09_1A)
            case .accentSoft:
                // accent mixed into paper: dark 16%, light 12% (color-mix equivalent)
                Variant(
                    light: 0xE4_DB_E6, dark: 0x2D_23_2E,
                    highContrastLight: 0xE1_DA_E3, highContrastDark: 0x2C_26_2C)
            case .warning:
                Variant(
                    light: 0x7A_4E_00, dark: 0xE3_B8_6A,
                    highContrastLight: 0x5C_3B_00, highContrastDark: 0xF0_CF_8E)
            case .danger:
                Variant(
                    light: 0xA1_1E_1E, dark: 0xFF_6B_6B,
                    highContrastLight: 0x7A_10_10, highContrastDark: 0xFF_B4_B4)
            case .control:
                Variant(
                    light: 0x86_89_91, dark: 0x7C_7F_88,
                    highContrastLight: 0x5E_61_69, highContrastDark: 0xA3_A6_AE)
            case .person:
                Variant(
                    light: 0x2D_5B_A6, dark: 0x8F_B3_F0,
                    highContrastLight: 0x1D_46_89, highContrastDark: 0xB8_D0_F8)
            case .place:
                Variant(
                    light: 0x1B_6B_43, dark: 0x7F_D1_A6,
                    highContrastLight: 0x11_52_2F, highContrastDark: 0xAE_E5_C6)
            }
        }
    }

    /// Published contrast ratios on paper from the Şafak design draft.
    /// Used only for verification; do not change palette values when these drift.
    enum DocumentedContrast {
        static let textOnPaper: [Double] = [16.32, 17.15, 18.39, 19.93]
        static let secondaryTextOnPaper: [Double] = [6.63, 8.25, 9.82, 12.90]
        static let tertiaryTextOnPaper: [Double] = [5.60, 6.08, 7.63, 9.92]
        static let accentOnPaper: [Double] = [7.86, 7.46, 10.52, 12.05]
        static let onAccentOnAccent: [Double] = [8.70, 7.28, 11.65, 11.76]
        static let warningOnPaper: [Double] = [6.50, 10.35, 9.11, 13.31]
        static let dangerOnPaper: [Double] = [6.97, 6.91, 9.93, 11.80]
        static let controlOnPaper: [Double] = [3.16, 4.79, 5.59, 8.18]
        static let personOnPaper: [Double] = [6.00, 9.02, 8.28, 12.73]
        static let placeOnPaper: [Double] = [5.87, 10.57, 8.35, 14.07]
    }

    static func sRGB(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    /// Relative luminance (WCAG 2.x), sRGB.
    static func relativeLuminance(hex: UInt32) -> Double {
        let (r, g, b) = sRGB(hex)
        func channel(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    static func contrastRatio(foreground: UInt32, background: UInt32) -> Double {
        let l1 = relativeLuminance(hex: foreground)
        let l2 = relativeLuminance(hex: background)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Porter-Duff src-over blend of an alpha foreground onto an opaque background.
    static func blend(foreground: UInt32, alpha: Double, over background: UInt32) -> UInt32 {
        let a = min(1, max(0, alpha))
        let (fr, fg, fb) = sRGB(foreground)
        let (br, bg, bb) = sRGB(background)
        let r = UInt32(((fr * a + br * (1 - a)) * 255).rounded()).clampedByte
        let g = UInt32(((fg * a + bg * (1 - a)) * 255).rounded()).clampedByte
        let b = UInt32(((fb * a + bb * (1 - a)) * 255).rounded()).clampedByte
        return (r << 16) | (g << 8) | b
    }

    /// Resolved opaque hex for a token on a background (alpha tokens are blended).
    static func resolvedHex(
        token: Token, appearance: Appearance, over background: UInt32? = nil
    ) -> UInt32 {
        let variant = token.variant
        let fg = variant.hex(for: appearance)
        let alpha = variant.alpha(for: appearance)
        if alpha >= 0.999 { return fg }
        let bg = background ?? Token.paper.variant.hex(for: appearance)
        return blend(foreground: fg, alpha: alpha, over: bg)
    }
}

private extension UInt32 {
    var clampedByte: UInt32 { Swift.min(255, self) }
}
