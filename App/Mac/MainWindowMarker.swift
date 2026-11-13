#if os(macOS)
    import AppKit
    import SwiftUI

    /// Lets the menu reopen an existing diary window before creating another one.
    struct MainWindowMarker: NSViewRepresentable {
        static let identifier = NSUserInterfaceItemIdentifier("kenet-main")

        func makeNSView(context: Context) -> MarkerView { MarkerView() }
        func updateNSView(_ view: MarkerView, context: Context) {}

        final class MarkerView: NSView {
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                window?.identifier = MainWindowMarker.identifier
            }
        }
    }
#endif
