import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

extension Color {
    /// Mürekkep warning token (`docs/design.md`): overdue date and mark only.
    /// Light `#7A4E00`, dark `#E2B865`. High-contrast variants arrive with Stage 9 tokens.
    static let inkWarning = Color(light: InkWarning.light, dark: InkWarning.dark)

    private init(light: Color, dark: Color) {
        #if canImport(AppKit)
            self.init(
                nsColor: NSColor(name: nil) { appearance in
                    let darkMatch = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    return NSColor(darkMatch ? dark : light)
                })
        #elseif canImport(UIKit)
            self.init(
                uiColor: UIColor { traits in
                    UIColor(traits.userInterfaceStyle == .dark ? dark : light)
                })
        #else
            self = light
        #endif
    }
}

private enum InkWarning {
    static let light = Color(red: 122 / 255, green: 78 / 255, blue: 0 / 255)
    static let dark = Color(red: 226 / 255, green: 184 / 255, blue: 101 / 255)
}
