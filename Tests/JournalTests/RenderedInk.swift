import SwiftUI
import Testing

@testable import Journal

/// Draws a view offscreen with `ImageRenderer` and reads which ink colors it really painted. A
/// test then asks "is the icon drawn in accent?" of the pixels instead of the source that picks
/// the color. Light appearance, on paper, at 4× so glyph strokes have an inside.
///
/// Only **core** pixels count: a pixel whose four neighbors are the same color (±4 per channel).
/// Anti-aliased edges blend two inks into a third tone (a control line over paper lands near the
/// well color, a text edge near secondary text); they never form such a core, so a color counts
/// only where the view really filled an area with it.
@MainActor
enum RenderedInk {
    nonisolated static let scale: CGFloat = 4
    nonisolated static let tolerance = 4

    struct Image {
        fileprivate let pixels: [UInt8]
        let width: Int
        let height: Int

        /// Core pixels of `color`.
        func count(_ color: Color) -> Int {
            coreIndices(of: color).count
        }

        /// The token's color, as `InkButtonChrome` resolves it.
        func count(_ token: InkButtonChrome.Token) -> Int {
            count(InkButtonChrome.color(for: token))
        }

        /// Share of the whole image filled (as core pixels) with the token's color.
        func share(_ token: InkButtonChrome.Token) -> Double {
            Double(count(token)) / Double(width * height)
        }

        /// The smallest rectangle (in pixels, top-left origin) holding every core pixel of `color`
        /// whose x is at least `fromX`; nil when none.
        func bounds(of color: Color, fromX: Int = 0) -> CGRect? {
            var minX = Int.max
            var minY = Int.max
            var maxX = -1
            var maxY = -1
            for (x, y) in coreIndices(of: color) where x >= fromX {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
            guard maxX >= 0 else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }

        private func coreIndices(of color: Color) -> [(Int, Int)] {
            let target = RenderedInk.rgb(color)
            func matches(_ x: Int, _ y: Int) -> Bool {
                guard x >= 0, y >= 0, x < width, y < height else { return false }
                let index = (y * width + x) * 4
                return pixels[index + 3] > 250
                    && abs(Int(pixels[index]) - target.0) <= RenderedInk.tolerance
                    && abs(Int(pixels[index + 1]) - target.1) <= RenderedInk.tolerance
                    && abs(Int(pixels[index + 2]) - target.2) <= RenderedInk.tolerance
            }
            var found: [(Int, Int)] = []
            for y in 0..<height {
                for x in 0..<width
                where matches(x, y) && matches(x - 1, y) && matches(x + 1, y) && matches(x, y - 1)
                    && matches(x, y + 1)
                {
                    found.append((x, y))
                }
            }
            return found
        }
    }

    /// Renders `view` on paper at `size`; `nil` when the renderer gives no image.
    static func image(_ view: some View, size: CGSize) -> Image? {
        let content =
            view
            .frame(width: size.width, height: size.height)
            .background(Color.ink.paper)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Image(pixels: pixels, width: width, height: height)
    }

    /// The color in light appearance, as 0…255 sRGB.
    nonisolated static func rgb(_ color: Color) -> (Int, Int, Int) {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        let resolved = color.resolve(in: environment)
        func channel(_ value: Float) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return (channel(resolved.red), channel(resolved.green), channel(resolved.blue))
    }
}
