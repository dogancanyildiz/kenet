import Foundation
import Testing

@testable import Journal

/// Reads asset-catalog color sets from the repo and checks WCAG contrast (`docs/design.md` rule 4).
struct PaletteContrastTests {
    private static let ratioTolerance = 0.05
    private static let bodyMinimum = 4.5
    private static let controlMinimum = 3.0

    @Test func catalogMatchesSwiftPalette() throws {
        for token in InkPalette.Token.allCases {
            let catalog = try Self.readCatalogVariant(token: token)
            let expected = token.variant
            #expect(catalog.light == expected.light, "\(token.rawValue) light")
            #expect(catalog.dark == expected.dark, "\(token.rawValue) dark")
            #expect(catalog.highContrastLight == expected.highContrastLight, "\(token.rawValue) HC light")
            #expect(catalog.highContrastDark == expected.highContrastDark, "\(token.rawValue) HC dark")
        }
    }

    @Test func accentColorAliasesInkAccent() throws {
        let accent = try Self.readCatalogVariant(assetName: "AccentColor")
        let ink = InkPalette.Token.accent.variant
        #expect(accent == ink)
    }

    @Test func textMeetsBodyContrastOnPaperAndSurface() {
        Self.assertBodyContrast(
            foreground: .text,
            backgrounds: [.paper, .surface],
            documentedOnPaper: InkPalette.DocumentedContrast.textOnPaper)
    }

    @Test func secondaryTextMeetsBodyContrastOnPaperAndSurface() {
        Self.assertBodyContrast(
            foreground: .secondaryText,
            backgrounds: [.paper, .surface],
            documentedOnPaper: InkPalette.DocumentedContrast.secondaryTextOnPaper)
    }

    @Test func accentMeetsBodyContrastOnPaper() {
        Self.assertBodyContrast(
            foreground: .accent,
            backgrounds: [.paper],
            documentedOnPaper: InkPalette.DocumentedContrast.accentOnPaper)
    }

    @Test func warningMeetsBodyContrastOnPaper() {
        Self.assertBodyContrast(
            foreground: .warning,
            backgrounds: [.paper],
            documentedOnPaper: InkPalette.DocumentedContrast.warningOnPaper)
    }

    @Test func dangerMeetsBodyContrastOnPaper() {
        Self.assertBodyContrast(
            foreground: .danger,
            backgrounds: [.paper],
            documentedOnPaper: InkPalette.DocumentedContrast.dangerOnPaper)
    }

    @Test func personMeetsBodyContrastOnPaper() {
        Self.assertBodyContrast(
            foreground: .person,
            backgrounds: [.paper],
            documentedOnPaper: InkPalette.DocumentedContrast.personOnPaper)
    }

    @Test func placeMeetsBodyContrastOnPaper() {
        Self.assertBodyContrast(
            foreground: .place,
            backgrounds: [.paper],
            documentedOnPaper: InkPalette.DocumentedContrast.placeOnPaper)
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

    // MARK: - Helpers

    private static func assertBodyContrast(
        foreground: InkPalette.Token,
        backgrounds: [InkPalette.Token],
        documentedOnPaper: [Double]
    ) {
        for background in backgrounds {
            for (index, appearance) in InkPalette.Appearance.allCases.enumerated() {
                let fg = foreground.variant.hex(for: appearance)
                let bg = background.variant.hex(for: appearance)
                let ratio = InkPalette.contrastRatio(foreground: fg, background: bg)
                #expect(
                    ratio + 0.000_1 >= bodyMinimum,
                    "\(foreground.rawValue) on \(background.rawValue) \(appearance.rawValue): \(ratio)")
                if background == .paper {
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

        for entry in colors {
            let appearances = entry["appearances"] as? [[String: String]] ?? []
            let hasDark = appearances.contains { $0["appearance"] == "luminosity" && $0["value"] == "dark" }
            let hasHighContrast = appearances.contains { $0["appearance"] == "contrast" && $0["value"] == "high" }
            let hex = try parseHex(from: entry)
            switch (hasDark, hasHighContrast) {
            case (false, false): light = hex
            case (true, false): dark = hex
            case (false, true): hcLight = hex
            case (true, true): hcDark = hex
            }
        }

        guard let light, let dark, let hcLight, let hcDark else {
            Issue.record("Incomplete color set \(assetName)")
            throw CatalogError.incomplete(assetName)
        }
        return InkPalette.Variant(
            light: light, dark: dark, highContrastLight: hcLight, highContrastDark: hcDark)
    }

    private static func parseHex(from entry: [String: Any]) throws -> UInt32 {
        guard
            let color = entry["color"] as? [String: Any],
            let components = color["components"] as? [String: String],
            let red = components["red"],
            let green = components["green"],
            let blue = components["blue"]
        else {
            throw CatalogError.badComponents
        }
        return (parseComponent(red) << 16) | (parseComponent(green) << 8) | parseComponent(blue)
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
