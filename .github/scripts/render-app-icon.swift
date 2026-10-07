#!/usr/bin/env swift
// Uygulama simgesini ("Geçme": mürdüm ve mürekkep) koddan üretir.
//
// Çıktı (depo köküne göre):
//   App/Support/AppIcon/*.svg                                  vektör kaynak (katmanlı)
//   App/Resources/Assets.xcassets/AppIcon.appiconset/*.png     iOS (üç görünüm) ve macOS (on boy)
//
// Kullanım: swift .github/scripts/render-app-icon.swift [çıktı kökü]
// Çıktı kökü verilmezse depo kökü kullanılır. Betik belirlenimcidir: aynı makinede yeniden
// çalıştırınca dosyalar bayt düzeyinde aynı kalır. Üçüncü taraf araç gerekmez.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - Renkler (docs/design.md belirteç tablosu)

struct RGB {
    let r: Double, g: Double, b: Double

    init(_ value: UInt32) {
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    }

    init(white: Double) {
        r = white
        g = white
        b = white
    }

    var hex: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

struct Palette {
    let background: RGB?
    let ink: RGB
    let accent: RGB
}

let lightPalette = Palette(background: RGB(0xFAF8F3), ink: RGB(0x1E1B17), accent: RGB(0x7A2C6E))
/// Koyu görünümde zemin yok: sistem kendi koyu zeminini koyar.
let darkPalette = Palette(background: nil, ink: RGB(0xEEE9DF), accent: RGB(0xE3A3D6))
/// Tonlu görünüm gri tonlamalı ve opaktır; iki şerit iki gri basamakla ayrışır.
let tintedPalette = Palette(background: RGB(white: 0), ink: RGB(white: 0.52), accent: RGB(white: 0.95))

// MARK: - Yol modeli (SVG ve CoreGraphics aynı parçalardan üretilir)

struct Vec {
    var x: Double
    var y: Double
}

enum Segment {
    case move(Vec)
    case line(Vec)
    /// Açılar y aşağı bakan tuval düzlemindedir; `increasing` artan açı yönü (ekranda saat yönü).
    case arc(center: Vec, radius: Double, from: Double, to: Double, increasing: Bool)
    case close
}

func point(on center: Vec, _ radius: Double, _ angle: Double) -> Vec {
    Vec(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
}

/// Sabit üç ondalık; sondaki sıfırlar atılır. Yerel ayardan bağımsızdır.
func num(_ value: Double) -> String {
    let scaled = (value * 1000).rounded()
    let negative = scaled < 0
    let whole = Int(abs(scaled))
    var text = "\(whole / 1000)"
    let frac = whole % 1000
    if frac != 0 {
        var digits = String(format: "%03d", frac)
        while digits.hasSuffix("0") { digits.removeLast() }
        text += "." + digits
    }
    return (negative && whole != 0 ? "-" : "") + text
}

func svgData(_ segments: [Segment]) -> String {
    var parts: [String] = []
    for segment in segments {
        switch segment {
        case .move(let p): parts.append("M\(num(p.x)) \(num(p.y))")
        case .line(let p): parts.append("L\(num(p.x)) \(num(p.y))")
        case .arc(let center, let radius, _, let to, let increasing):
            let end = point(on: center, radius, to)
            // Bu çizimde hiçbir yay 180 dereceyi aşmaz.
            parts.append("A\(num(radius)) \(num(radius)) 0 0 \(increasing ? 1 : 0) \(num(end.x)) \(num(end.y))")
        case .close: parts.append("Z")
        }
    }
    return parts.joined(separator: " ")
}

func cgPath(_ segments: [Segment]) -> CGPath {
    let path = CGMutablePath()
    for segment in segments {
        switch segment {
        case .move(let p): path.move(to: CGPoint(x: p.x, y: p.y))
        case .line(let p): path.addLine(to: CGPoint(x: p.x, y: p.y))
        case .arc(let center, let radius, let from, let to, let increasing):
            path.addArc(
                center: CGPoint(x: center.x, y: center.y), radius: radius,
                startAngle: from, endAngle: to, clockwise: !increasing)
        case .close: path.closeSubpath()
        }
    }
    return path
}

// MARK: - Geometri

/// İki uzun halka (kapsül) dik açıyla birbirinin içinden geçer. Ölçüler tuval birimindedir.
struct Mark {
    /// Halka merkez çizgisinin düz kısmının yarı boyu.
    var half: Double
    /// Halka merkez çizgisinin uç yarıçapı.
    var radius: Double
    /// Şerit kalınlığı.
    var width: Double
    /// Üstten geçen şeridin iki yanında bırakılan boşluk.
    var gap: Double

    var outer: Double { radius + width / 2 }
    var inner: Double { radius - width / 2 }

    /// Bir halkanın yarısı: alttan geçtiği iki yerde gerçekten kesilmiş kapalı yol.
    /// `quarter` 0...3: parça merkez çevresinde 90 derecelik adımlarla döner; 0 ve 2 bir halkayı,
    /// 1 ve 3 öteki halkayı verir.
    ///
    /// Yerel çerçeve: u halka ekseni, v ona dik. Parça v = +radius kenarı boyunca u = nearCut'tan
    /// sola gider, sol ucu döner ve öteki kenarda u = -farCut doğrusunda biter. İki kesim de üstten
    /// geçen şeridin kenarına koşuttur; boşluk her yerde `gap` kadardır.
    func piece(quarter: Int, center: Vec) -> [Segment] {
        let nearCut = inner - gap
        let farCut = outer + gap
        let overhang = farCut - half
        precondition(nearCut > 0, "boşluk iç açıklıktan büyük")
        precondition(overhang > 0 && overhang < inner * 0.9, "uzak kesim ucun yayına düşmeli")

        let theta = Double.pi / 4 + Double(quarter) * Double.pi / 2
        func place(_ u: Double, _ v: Double) -> Vec {
            Vec(x: center.x + u * cos(theta) - v * sin(theta), y: center.y + u * sin(theta) + v * cos(theta))
        }
        let cap = place(-half, 0)
        let quarterTurn = Double.pi / 2
        // Uzak kesimin dış ve iç çemberi kestiği açılar (yerel çerçevede 180 ile 270 derece arası).
        let outerEnd = Double.pi + acos(overhang / outer)
        let innerEnd = Double.pi + acos(overhang / inner)

        return [
            .move(place(nearCut, outer)),
            .line(place(-half, outer)),
            .arc(center: cap, radius: outer, from: theta + quarterTurn, to: theta + outerEnd, increasing: true),
            .line(point(on: cap, inner, theta + innerEnd)),
            .arc(center: cap, radius: inner, from: theta + innerEnd, to: theta + quarterTurn, increasing: false),
            .line(place(nearCut, inner)),
            .close,
        ]
    }
}

/// Mac simgesinin kendi gövdesi: yuvarlak köşeli kare ve sistemin simge şablonundaki hafif alt gölge.
struct Body {
    var inset: Double
    var cornerRadius: Double
    /// Gölge: aşağı kayma, bulanıklık, karalık. Küçük boylarda yoktur.
    var shadow: (offset: Double, blur: Double, alpha: Double)?
}

struct Design {
    var name: String
    var canvas: Double
    var mark: Mark
    var body: Body?
    var palette: Palette

    var center: Vec { Vec(x: canvas / 2, y: canvas / 2) }
    var accentPieces: [[Segment]] { [0, 2].map { mark.piece(quarter: $0, center: center) } }
    var inkPieces: [[Segment]] { [1, 3].map { mark.piece(quarter: $0, center: center) } }
}

/// iOS çizimi: 1024 tuval, taslaktaki ölçüler.
let baseMark = Mark(half: 168, radius: 132, width: 86, gap: 30)

/// Mac gövdesi: macOS simge ızgarası (1024 tuvalde 824 gövde, 100 kenar payı).
let macBodyRatio = 824.0 / 1024.0
let macCornerRatio = 0.225

func macDesign(name: String) -> Design {
    let side = 824.0
    let scale = macBodyRatio
    return Design(
        name: name, canvas: 1024,
        mark: Mark(
            half: baseMark.half * scale, radius: baseMark.radius * scale,
            width: baseMark.width * scale, gap: baseMark.gap * scale),
        body: Body(inset: 100, cornerRadius: side * macCornerRatio, shadow: (offset: 10, blur: 20, alpha: 0.28)),
        palette: lightPalette)
}

/// Küçük Mac boyları: tuval birimi pikseldir; gövde kenarları ve merkez tam piksele oturur. Şerit ve
/// boşluk kalınlaştırılmıştır; ölçüler köşegen adımıyla verilir (bir adım 1/√2 piksel: 45 derecelik
/// şeridin kenarı piksel köşegenleri üstünde yürür).
func smallMacDesign(
    pixels: Int, bodySide: Int, innerSteps: Double, widthSteps: Double, gapSteps: Double, halfSteps: Double
) -> Design {
    let step = 0.5.squareRoot()
    let width = widthSteps * step
    return Design(
        name: "app-icon-mac-\(pixels)", canvas: Double(pixels),
        mark: Mark(
            half: halfSteps * step, radius: innerSteps * step + width / 2, width: width, gap: gapSteps * step),
        body: Body(
            inset: Double(pixels - bodySide) / 2, cornerRadius: Double(bodySide) * macCornerRatio, shadow: nil),
        palette: lightPalette)
}

let iosLight = Design(name: "app-icon", canvas: 1024, mark: baseMark, body: nil, palette: lightPalette)
let iosDark = Design(name: "app-icon-dark", canvas: 1024, mark: baseMark, body: nil, palette: darkPalette)
let iosTinted = Design(name: "app-icon-tinted", canvas: 1024, mark: baseMark, body: nil, palette: tintedPalette)
let macLarge = macDesign(name: "app-icon-mac")
let mac16 = smallMacDesign(pixels: 16, bodySide: 14, innerSteps: 1.5, widthSteps: 2.5, gapSteps: 1, halfSteps: 4)
let mac32 = smallMacDesign(pixels: 32, bodySide: 26, innerSteps: 3, widthSteps: 5, gapSteps: 2, halfSteps: 8)

// MARK: - SVG

func svg(_ design: Design) -> String {
    let size = num(design.canvas)
    var lines: [String] = []
    lines.append(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(size) \(size)\" "
            + "width=\"\(size)\" height=\"\(size)\">")
    lines.append("  <title>Geçme</title>")
    if let body = design.body, let background = design.palette.background {
        let side = num(design.canvas - 2 * body.inset)
        var filter = ""
        if let shadow = body.shadow {
            lines.append("  <defs>")
            lines.append(
                "    <filter id=\"body-shadow\" x=\"-10%\" y=\"-10%\" width=\"120%\" height=\"125%\">")
            lines.append(
                "      <feDropShadow dx=\"0\" dy=\"\(num(shadow.offset))\" stdDeviation=\"\(num(shadow.blur / 2))\" "
                    + "flood-color=\"#000000\" flood-opacity=\"\(num(shadow.alpha))\"/>")
            lines.append("    </filter>")
            lines.append("  </defs>")
            filter = " filter=\"url(#body-shadow)\""
        }
        lines.append("  <g id=\"background\" fill=\"\(background.hex)\"\(filter)>")
        lines.append(
            "    <rect x=\"\(num(body.inset))\" y=\"\(num(body.inset))\" width=\"\(side)\" height=\"\(side)\" "
                + "rx=\"\(num(body.cornerRadius))\"/>")
        lines.append("  </g>")
    } else if let background = design.palette.background {
        lines.append("  <g id=\"background\" fill=\"\(background.hex)\">")
        lines.append("    <rect width=\"\(size)\" height=\"\(size)\"/>")
        lines.append("  </g>")
    }
    lines.append("  <g id=\"ink-strip\" fill=\"\(design.palette.ink.hex)\">")
    for piece in design.inkPieces { lines.append("    <path d=\"\(svgData(piece))\"/>") }
    lines.append("  </g>")
    lines.append("  <g id=\"accent-strip\" fill=\"\(design.palette.accent.hex)\">")
    for piece in design.accentPieces { lines.append("    <path d=\"\(svgData(piece))\"/>") }
    lines.append("  </g>")
    lines.append("</svg>")
    return lines.joined(separator: "\n") + "\n"
}

// MARK: - PNG

enum PixelFormat {
    /// Alfa kanalı yok (App Store'a giden açık görünüm).
    case opaqueColor
    /// Saydam zemin (koyu görünüm, Mac gövdesi).
    case transparentColor
    /// Gri tonlamalı, alfa kanalı yok (tonlu görünüm).
    case opaqueGray
}

func cgColor(_ color: RGB, alpha: Double = 1, in space: CGColorSpace) -> CGColor {
    if space.model == .monochrome {
        return CGColor(colorSpace: space, components: [color.r, alpha])!
    }
    return CGColor(colorSpace: space, components: [color.r, color.g, color.b, alpha])!
}

func render(_ design: Design, pixels: Int, format: PixelFormat) -> CGImage {
    let space: CGColorSpace
    let alpha: CGImageAlphaInfo
    switch format {
    case .opaqueColor:
        space = CGColorSpace(name: CGColorSpace.sRGB)!
        alpha = .noneSkipLast
    case .transparentColor:
        space = CGColorSpace(name: CGColorSpace.sRGB)!
        alpha = .premultipliedLast
    case .opaqueGray:
        space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
        alpha = .none
    }
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: alpha.rawValue)!
    let scale = Double(pixels) / design.canvas
    // Tuval sol üstten başlar, y aşağı bakar (SVG ile aynı).
    context.translateBy(x: 0, y: Double(pixels))
    context.scaleBy(x: scale, y: -scale)
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)

    let full = CGRect(x: 0, y: 0, width: design.canvas, height: design.canvas)
    if let body = design.body, let background = design.palette.background {
        let rect = full.insetBy(dx: body.inset, dy: body.inset)
        let path = CGPath(
            roundedRect: rect, cornerWidth: body.cornerRadius, cornerHeight: body.cornerRadius, transform: nil)
        context.saveGState()
        if let shadow = body.shadow {
            // Gölge ölçüleri dönüşümden etkilenmez; piksel cinsinden verilir.
            context.setShadow(
                offset: CGSize(width: 0, height: -shadow.offset * scale), blur: shadow.blur * scale,
                color: CGColor(colorSpace: space, components: [0, 0, 0, shadow.alpha])!)
        }
        context.addPath(path)
        context.setFillColor(cgColor(background, in: space))
        context.fillPath()
        context.restoreGState()
    } else if let background = design.palette.background {
        context.setFillColor(cgColor(background, in: space))
        context.fill(full)
    }
    for (pieces, color) in [(design.inkPieces, design.palette.ink), (design.accentPieces, design.palette.accent)] {
        for piece in pieces { context.addPath(cgPath(piece)) }
        context.setFillColor(cgColor(color, in: space))
        context.fillPath()
    }
    return context.makeImage()!
}

// PNG, ImageIO ile kodlanır; ardından yalnız zorunlu parçalar (IHDR, IDAT, IEND) ve renk uzayını
// bildiren sRGB / gAMA parçaları bırakılır. Böylece dosyada tarih, yazılım adı ya da başka meta veri kalmaz.

func encodePNG(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG kodlanamadı") }
    return stripped(data as Data)
}

func stripped(_ png: Data) -> Data {
    let keep: Set<String> = ["IHDR", "sRGB", "gAMA", "IDAT", "IEND"]
    let bytes = [UInt8](png)
    var out = Data(bytes[0..<8])
    var offset = 8
    while offset + 12 <= bytes.count {
        let length = bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
        let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
        let end = offset + 12 + length
        if keep.contains(type) { out.append(contentsOf: bytes[offset..<end]) }
        offset = end
    }
    return out
}

// MARK: - Üretim

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let outputRoot =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) : repositoryRoot
let svgDirectory = outputRoot.appendingPathComponent("App/Support/AppIcon", isDirectory: true)
let iconDirectory = outputRoot.appendingPathComponent(
    "App/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

func write(_ data: Data, to directory: URL, _ name: String) {
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    } catch {
        fatalError("yazılamadı: \(name): \(error)")
    }
}

for design in [iosLight, iosDark, iosTinted, macLarge, mac16, mac32] {
    write(Data(svg(design).utf8), to: svgDirectory, design.name + ".svg")
}

let iosFiles: [(design: Design, format: PixelFormat, name: String)] = [
    (iosLight, .opaqueColor, "AppIcon-iOS-Default-1024.png"),
    (iosDark, .transparentColor, "AppIcon-iOS-Dark-1024.png"),
    (iosTinted, .opaqueGray, "AppIcon-iOS-Tinted-1024.png"),
]
for file in iosFiles {
    write(encodePNG(render(file.design, pixels: 1024, format: file.format)), to: iconDirectory, file.name)
}

/// macOS: nokta boyu, ölçek, çizim. 16 ve 32 piksel ayrı çizimdir; ötekiler büyük çizimden üretilir.
let macFiles: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
for file in macFiles {
    let pixels = file.points * file.scale
    let design: Design
    switch pixels {
    case 16: design = mac16
    case 32: design = mac32
    default: design = macLarge
    }
    let suffix = file.scale == 1 ? "" : "@\(file.scale)x"
    write(
        encodePNG(render(design, pixels: pixels, format: .transparentColor)), to: iconDirectory,
        "AppIcon-macOS-\(file.points)\(suffix).png")
}

print("Simge üretildi: 6 SVG, 13 PNG")
