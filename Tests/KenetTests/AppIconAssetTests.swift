import Foundation
import Testing

/// Guards the committed app icon set: every declared file exists at its declared pixel size, iOS has
/// all three appearances, and the marketing icon carries no alpha. Reads files only; it does not rerun
/// `.github/scripts/render-app-icon.swift`.
struct AppIconAssetTests {
    @Test func everyDeclaredFileExistsAtDeclaredPixelSize() throws {
        let entries = try Self.entries()
        #expect(entries.count == 13)
        for entry in entries {
            let header = try Self.header(of: entry.filename)
            #expect(header.width == entry.pixels, "\(entry.filename) width")
            #expect(header.height == entry.pixels, "\(entry.filename) height")
            #expect(header.bitDepth == 8, "\(entry.filename) bit depth")
        }
    }

    @Test func noStrayOrUndeclaredFiles() throws {
        let declared = Set(try Self.entries().map(\.filename))
        let onDisk = Set(
            try FileManager.default.contentsOfDirectory(atPath: Self.iconSet().path)
                .filter { $0.hasSuffix(".png") })
        #expect(declared == onDisk)
    }

    @Test func iOSDeclaresDefaultDarkAndTinted() throws {
        let ios = try Self.entries().filter { $0.platform == "ios" }
        #expect(ios.map(\.appearance).sorted() == ["dark", "default", "tinted"])
        #expect(ios.allSatisfy { $0.idiom == "universal" && $0.pixels == 1024 })
    }

    @Test func macDeclaresTenSizes() throws {
        let mac = try Self.entries().filter { $0.idiom == "mac" }
        #expect(mac.map(\.pixels).sorted() == [16, 32, 32, 64, 128, 256, 256, 512, 512, 1024])
        for entry in mac {
            // The Mac icon carries its own rounded body and margin, so it needs transparency.
            #expect(try Self.header(of: entry.filename).colorType == PNGHeader.rgba, "\(entry.filename)")
        }
    }

    /// App Store rejects a marketing icon with an alpha channel.
    @Test func defaultAppearanceHasNoAlpha() throws {
        let entry = try #require(try Self.entries().first { $0.platform == "ios" && $0.appearance == "default" })
        let header = try Self.header(of: entry.filename)
        #expect(header.colorType == PNGHeader.rgb)
        #expect(!header.chunks.contains("tRNS"))
    }

    /// Dark sits on the system background (transparent); tinted is opaque grayscale.
    @Test func darkIsTransparentAndTintedIsOpaqueGray() throws {
        let ios = try Self.entries().filter { $0.platform == "ios" }
        let dark = try #require(ios.first { $0.appearance == "dark" })
        let tinted = try #require(ios.first { $0.appearance == "tinted" })
        #expect(try Self.header(of: dark.filename).colorType == PNGHeader.rgba)
        let tintedHeader = try Self.header(of: tinted.filename)
        #expect(tintedHeader.colorType == PNGHeader.gray)
        #expect(!tintedHeader.chunks.contains("tRNS"))
    }

    /// No dates, software names or paths: only pixel data and the color space marker.
    @Test func filesCarryNoMetadata() throws {
        let allowed: Set<String> = ["IHDR", "sRGB", "gAMA", "IDAT", "IEND"]
        for entry in try Self.entries() {
            let extra = try Self.header(of: entry.filename).chunks.subtracting(allowed)
            #expect(extra.isEmpty, "\(entry.filename): \(extra.sorted())")
        }
    }

    // MARK: - Reading

    private struct Entry {
        let filename: String
        let idiom: String
        let platform: String?
        let appearance: String
        let pixels: Int
    }

    private struct PNGHeader {
        static let gray: UInt8 = 0
        static let rgb: UInt8 = 2
        static let rgba: UInt8 = 6

        let width: Int
        let height: Int
        let bitDepth: UInt8
        let colorType: UInt8
        let chunks: Set<String>
    }

    private struct Catalog: Decodable {
        struct Image: Decodable {
            struct Appearance: Decodable {
                let appearance: String
                let value: String
            }

            let filename: String?
            let idiom: String
            let platform: String?
            let scale: String?
            let size: String
            let appearances: [Appearance]?
        }

        let images: [Image]
    }

    private static func entries() throws -> [Entry] {
        let data = try Data(contentsOf: iconSet().appendingPathComponent("Contents.json"))
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        return try catalog.images.map { image in
            let filename = try #require(image.filename, "every slot needs a file")
            let points = try #require(Int(image.size.split(separator: "x").first ?? ""))
            let scale = try #require(Int((image.scale ?? "1x").dropLast()))
            return Entry(
                filename: filename, idiom: image.idiom, platform: image.platform,
                appearance: image.appearances?.first { $0.appearance == "luminosity" }?.value ?? "default",
                pixels: points * scale)
        }
    }

    private static func header(of filename: String) throws -> PNGHeader {
        let bytes = [UInt8](try Data(contentsOf: iconSet().appendingPathComponent(filename)))
        try #require(bytes.count > 33, "\(filename) is too short")
        #expect(Array(bytes[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "\(filename) signature")
        func number(at offset: Int) -> Int {
            bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        }
        var chunks: Set<String> = []
        var offset = 8
        while offset + 12 <= bytes.count {
            chunks.insert(String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self))
            offset += 12 + number(at: offset)
        }
        return PNGHeader(
            width: number(at: 16), height: number(at: 20), bitDepth: bytes[24], colorType: bytes[25],
            chunks: chunks)
    }

    private static func iconSet(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
    }
}
