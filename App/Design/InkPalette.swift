import Foundation

/// Hex values for the Mürekkep palette (`docs/design.md`).
/// Asset catalog color sets must match these; ``PaletteContrastTests`` enforces that.
enum InkPalette {
    struct Variant: Equatable, Sendable {
        let light: UInt32
        let dark: UInt32
        let highContrastLight: UInt32
        let highContrastDark: UInt32

        func hex(for appearance: Appearance) -> UInt32 {
            switch appearance {
            case .light: light
            case .dark: dark
            case .highContrastLight: highContrastLight
            case .highContrastDark: highContrastDark
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
        case surface
        case well
        case rule
        case text
        case secondaryText
        case accent
        case onAccent
        case warning
        case danger
        case control
        case person
        case place

        var assetName: String {
            switch self {
            case .paper: "InkPaper"
            case .surface: "InkSurface"
            case .well: "InkWell"
            case .rule: "InkRule"
            case .text: "InkText"
            case .secondaryText: "InkSecondaryText"
            case .accent: "InkAccent"
            case .onAccent: "InkOnAccent"
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
                Variant(
                    light: 0xFA_F8_F3, dark: 0x18_16_14,
                    highContrastLight: 0xFA_F8_F3, highContrastDark: 0x14_12_10)
            case .surface:
                Variant(
                    light: 0xFF_FF_FF, dark: 0x23_20_1C,
                    highContrastLight: 0xFF_FF_FF, highContrastDark: 0x1E_1B_18)
            case .well:
                Variant(
                    light: 0xF1_ED_E4, dark: 0x11_0F_0E,
                    highContrastLight: 0xEC_E7_DC, highContrastDark: 0x0C_0B_0A)
            case .rule:
                Variant(
                    light: 0xE2_DC_CF, dark: 0x30_2C_27,
                    highContrastLight: 0xC4_BB_AB, highContrastDark: 0x4C_46_3E)
            case .text:
                Variant(
                    light: 0x1E_1B_17, dark: 0xEE_E9_DF,
                    highContrastLight: 0x0E_0C_0A, highContrastDark: 0xFF_FD_F8)
            case .secondaryText:
                Variant(
                    light: 0x57_51_4A, dark: 0xB5_AD_9F,
                    highContrastLight: 0x40_3B_35, highContrastDark: 0xD6_CF_C2)
            case .accent:
                Variant(
                    light: 0x7A_2C_6E, dark: 0xE3_A3_D6,
                    highContrastLight: 0x5E_1F_55, highContrastDark: 0xED_C3_E5)
            case .onAccent:
                Variant(
                    light: 0xFF_FF_FF, dark: 0x1A_10_22,
                    highContrastLight: 0xFF_FF_FF, highContrastDark: 0x12_09_1A)
            case .warning:
                Variant(
                    light: 0x7A_4E_00, dark: 0xE2_B8_65,
                    highContrastLight: 0x5C_3B_00, highContrastDark: 0xF0_CF_8E)
            case .danger:
                Variant(
                    light: 0xA1_1E_1E, dark: 0xF0_71_78,
                    highContrastLight: 0x7A_10_10, highContrastDark: 0xFF_B4_B4)
            case .control:
                Variant(
                    light: 0x8C_84_78, dark: 0x7E_77_6C,
                    highContrastLight: 0x65_5E_54, highContrastDark: 0xA3_9B_8F)
            case .person:
                Variant(
                    light: 0x2D_5B_A6, dark: 0x8F_B3_F0,
                    highContrastLight: 0x1D_46_89, highContrastDark: 0xB3_CD_F8)
            case .place:
                Variant(
                    light: 0x38_6E_43, dark: 0x8F_CB_9C,
                    highContrastLight: 0x24_56_2E, highContrastDark: 0xAE_DD_B8)
            }
        }
    }

    /// Published contrast ratios on paper from `docs/design.md` (parenthetical values).
    /// Used only for verification; do not change palette values when these drift.
    enum DocumentedContrast {
        static let textOnPaper: [Double] = [16.16, 14.91, 18.39, 18.38]
        static let secondaryTextOnPaper: [Double] = [7.38, 8.11, 10.44, 12.07]
        static let accentOnPaper: [Double] = [8.20, 9.00, 10.97, 12.05]
        static let onAccentOnAccent: [Double] = [8.70, 9.18, 11.65, 12.54]
        static let warningOnPaper: [Double] = [6.78, 9.69, 9.51, 12.48]
        /// Measured for `danger` (error / destructive); not listed in `docs/design.md` yet.
        static let dangerOnPaper: [Double] = [7.27, 6.31, 10.36, 11.07]
        static let controlOnPaper: [Double] = [3.48, 4.08, 6.03, 6.80]
        static let personOnPaper: [Double] = [6.26, 8.49, 8.64, 11.57]
        static let placeOnPaper: [Double] = [5.69, 9.62, 8.09, 12.31]
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
}
