import Foundation
import Testing

@testable import Journal

/// Reads asset-catalog color sets from the repo and checks WCAG contrast (Şafak rule 4).
struct PaletteContrastTests {
    private static let ratioTolerance = 0.05
    private static let bodyMinimum = 4.5
    private static let controlMinimum = 3.0

    private static let textTokens: [InkPalette.Token] = [
        .text, .secondaryText, .tertiaryText, .accent, .warning, .danger, .person, .place,
    ]
    private static let textBackgrounds: [InkPalette.Token] = [.paper, .surface, .well]

    @Test func catalogMatchesSwiftPalette() throws {
        for token in InkPalette.Token.allCases {
            let catalog = try Self.readCatalogVariant(token: token)
            let expected = token.variant
            #expect(catalog.light == expected.light, "\(token.rawValue) light")
            #expect(catalog.dark == expected.dark, "\(token.rawValue) dark")
            #expect(catalog.highContrastLight == expected.highContrastLight, "\(token.rawValue) HC light")
            #expect(catalog.highContrastDark == expected.highContrastDark, "\(token.rawValue) HC dark")
            #expect(
                abs(catalog.lightAlpha - expected.lightAlpha) < 0.001,
                "\(token.rawValue) light alpha")
            #expect(
                abs(catalog.darkAlpha - expected.darkAlpha) < 0.001,
                "\(token.rawValue) dark alpha")
            #expect(
                abs(catalog.highContrastLightAlpha - expected.highContrastLightAlpha) < 0.001,
                "\(token.rawValue) HC light alpha")
            #expect(
                abs(catalog.highContrastDarkAlpha - expected.highContrastDarkAlpha) < 0.001,
                "\(token.rawValue) HC dark alpha")
        }
    }

    @Test func accentColorAliasesInkAccent() throws {
        let accent = try Self.readCatalogVariant(assetName: "AccentColor")
        let ink = InkPalette.Token.accent.variant
        #expect(accent.light == ink.light)
        #expect(accent.dark == ink.dark)
        #expect(accent.highContrastLight == ink.highContrastLight)
        #expect(accent.highContrastDark == ink.highContrastDark)
    }

    @Test func textTokensMeetBodyContrastOnPaperSurfaceAndWell() {
        for foreground in Self.textTokens {
            Self.assertBodyContrast(
                foreground: foreground,
                backgrounds: Self.textBackgrounds,
                documentedOnPaper: Self.documentedOnPaper(for: foreground))
        }
    }

    @Test func onAccentMeetsBodyContrastOnAccent() {
        for (index, appearance) in InkPalette.Appearance.allCases.enumerated() {
            let fg = InkPalette.Token.onAccent.variant.hex(for: appearance)
            let bg = InkPalette.Token.accent.variant.hex(for: appearance)
            let ratio = InkPalette.contrastRatio(foreground: fg, background: bg)
            #expect(
                ratio + 0.000_1 >= Self.bodyMinimum,
                "onAccent on accent \(appearance.rawValue): \(ratio)")
            let documented = InkPalette.DocumentedContrast.onAccentOnAccent[index]
            #expect(
                abs(ratio - documented) <= Self.ratioTolerance,
                "onAccent documented \(appearance.rawValue): got \(ratio), table \(documented)")
        }
    }

    @Test func controlMeetsNonTextContrastOnPaper() {
        for (index, appearance) in InkPalette.Appearance.allCases.enumerated() {
            let fg = InkPalette.Token.control.variant.hex(for: appearance)
            let bg = InkPalette.Token.paper.variant.hex(for: appearance)
            let ratio = InkPalette.contrastRatio(foreground: fg, background: bg)
            #expect(
                ratio + 0.000_1 >= Self.controlMinimum,
                "control on paper \(appearance.rawValue): \(ratio)")
            let documented = InkPalette.DocumentedContrast.controlOnPaper[index]
            #expect(
                abs(ratio - documented) <= Self.ratioTolerance,
                "control documented \(appearance.rawValue): got \(ratio), table \(documented)")
        }
    }

    /// `line` is an alpha token; contrast is measured after blending onto paper.
    /// Design draft notes the blended ratio is ~1.3–2.0 (decorative). Control carries the 3:1 UI chrome.
    @Test func lineBlendedOnPaperIsMeasurable() {
        for appearance in InkPalette.Appearance.allCases {
            let paper = InkPalette.Token.paper.variant.hex(for: appearance)
            let blended = InkPalette.resolvedHex(token: .line, appearance: appearance, over: paper)
            let ratio = InkPalette.contrastRatio(foreground: blended, background: paper)
            #expect(ratio > 1.0, "line blended on paper \(appearance.rawValue): \(ratio)")
        }
    }

    @Test func glowPeaksMeetBodyContrastForAllowedTokens() {
        let tokens: [InkPalette.Token] = [.text, .secondaryText, .accent, .warning]
        for peak in InkPalette.GlowPeak.allCases {
            for token in tokens {
                let fg = token.variant.hex(for: peak.appearance)
                let ratio = InkPalette.contrastRatio(foreground: fg, background: peak.hex)
                #expect(
                    ratio + 0.000_1 >= Self.bodyMinimum,
                    "\(token.rawValue) on glow \(peak.rawValue): \(ratio)")
            }
        }
    }

    // MARK: - Helpers

    private static func documentedOnPaper(for token: InkPalette.Token) -> [Double]? {
        switch token {
        case .text: InkPalette.DocumentedContrast.textOnPaper
        case .secondaryText: InkPalette.DocumentedContrast.secondaryTextOnPaper
        case .tertiaryText: InkPalette.DocumentedContrast.tertiaryTextOnPaper
        case .accent: InkPalette.DocumentedContrast.accentOnPaper
        case .warning: InkPalette.DocumentedContrast.warningOnPaper
        case .danger: InkPalette.DocumentedContrast.dangerOnPaper
        case .person: InkPalette.DocumentedContrast.personOnPaper
        case .place: InkPalette.DocumentedContrast.placeOnPaper
        default: nil
        }
    }

    private static func assertBodyContrast(
        foreground: InkPalette.Token,
        backgrounds: [InkPalette.Token],
        documentedOnPaper: [Double]?
    ) {
        for background in backgrounds {
            for (index, appearance) in InkPalette.Appearance.allCases.enumerated() {
                let fg = foreground.variant.hex(for: appearance)
                let bg = background.variant.hex(for: appearance)
                let ratio = InkPalette.contrastRatio(foreground: fg, background: bg)
                #expect(
                    ratio + 0.000_1 >= bodyMinimum,
                    "\(foreground.rawValue) on \(background.rawValue) \(appearance.rawValue): \(ratio)")
                if background == .paper, let documentedOnPaper {
                    let documented = documentedOnPaper[index]
                    #expect(
                        abs(ratio - documented) <= ratioTolerance,
                        "\(foreground.rawValue) documented \(appearance.rawValue): got \(ratio), table \(documented)")
                }
            }
        }
    }

    private static func readCatalogVariant(token: InkPalette.Token) throws -> InkPalette.Variant {
        try readCatalogVariant(assetName: token.assetName)
    }

    private static func readCatalogVariant(assetName: String) throws -> InkPalette.Variant {
        let url = repositoryRoot()
            .appendingPathComponent("App/Resources/Assets.xcassets/\(assetName).colorset/Contents.json")
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let colors = root?["colors"] as? [[String: Any]] ?? []
        var light: UInt32?
        var dark: UInt32?
        var hcLight: UInt32?
        var hcDark: UInt32?
        var lightAlpha: Double?
        var darkAlpha: Double?
        var hcLightAlpha: Double?
        var hcDarkAlpha: Double?

        for entry in colors {
            let appearances = entry["appearances"] as? [[String: String]] ?? []
            let hasDark = appearances.contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" }
            let hasHighContrast = appearances.contains { $0["appearance"] == "contrast" && $0["value"] == "high" }
            let (hex, alpha) = try parseColor(from: entry)
            switch (hasDark, hasHighContrast) {
            case (false, false):
                light = hex
                lightAlpha = alpha
            case (true, false):
                dark = hex
                darkAlpha = alpha
            case (false, true):
                hcLight = hex
                hcLightAlpha = alpha
            case (true, true):
                hcDark = hex
                hcDarkAlpha = alpha
            }
        }

        guard let light, let dark, let hcLight, let hcDark,
            let lightAlpha, let darkAlpha, let hcLightAlpha, let hcDarkAlpha
        else {
            Issue.record("Incomplete color set \(assetName)")
            throw CatalogError.incomplete(assetName)
        }
        return InkPalette.Variant(
            light: light, dark: dark, highContrastLight: hcLight, highContrastDark: hcDark,
            lightAlpha: lightAlpha, darkAlpha: darkAlpha,
            highContrastLightAlpha: hcLightAlpha, highContrastDarkAlpha: hcDarkAlpha)
    }

    private static func parseColor(from entry: [String: Any]) throws -> (UInt32, Double) {
        guard
            let color = entry["color"] as? [String: Any],
            let components = color["components"] as? [String: String],
            let red = components["red"],
            let green = components["green"],
            let blue = components["blue"]
        else {
            throw CatalogError.badComponents
        }
        let hex = (parseComponent(red) << 16) | (parseComponent(green) << 8) | parseComponent(blue)
        let alpha = parseAlpha(components["alpha"] ?? "1")
        return (hex, alpha)
    }

    private static func parseComponent(_ raw: String) -> UInt32 {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            return UInt32(raw.dropFirst(2), radix: 16) ?? 0
        }
        if let unit = Double(raw) {
            return UInt32((unit * 255).rounded())
        }
        return 0
    }

    private static func parseAlpha(_ raw: String) -> Double {
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            let value = Double(UInt32(raw.dropFirst(2), radix: 16) ?? 255)
            return value / 255
        }
        return Double(raw) ?? 1
    }

    private static func repositoryRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private enum CatalogError: Error {
        case incomplete(String)
        case badComponents
    }
}
