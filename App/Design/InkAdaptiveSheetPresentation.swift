import SwiftUI

struct InkAdaptiveSheetPresentation: ViewModifier {
    @Environment(\.shellKind) private var shellKind
    var usesPhoneDetents = true
    var fitsContent = false

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
            switch InkSheetSizing.resolve(
                shell: shellKind, fitsContent: fitsContent, usesPhoneDetents: usesPhoneDetents)
            {
            case .fittedForm:
                content
                    .frame(minWidth: InkSheetChrome.macMinWidth, idealWidth: InkSheetChrome.macIdealWidth)
                    .presentationSizing(.form.fitted(horizontal: false, vertical: true))
            case .form:
                content
                    .frame(
                        minWidth: InkSheetChrome.macMinWidth, idealWidth: InkSheetChrome.macIdealWidth,
                        minHeight: InkSheetChrome.macMinHeight, idealHeight: InkSheetChrome.macIdealHeight
                    )
            case .detents:
                content.presentationDetents([.medium, .large])
            case .plain:
                content
            }
        #else
            if usesPhoneDetents {
                content.presentationDetents([.medium, .large])
            } else {
                content
            }
        #endif
    }
}
