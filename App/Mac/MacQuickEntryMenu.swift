#if os(macOS)
    import AppKit
    import SwiftUI

    struct MacQuickEntryMenu: View {
        let controller: MacQuickEntryController
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Button {
                controller.open()
            } label: {
                Text("Hızlı giriş (\(controller.shortcut.shortcut.display))")
            }
            if let error = controller.shortcut.errorText {
                Text(verbatim: error)
            }
            Button("Uygulamayı aç") {
                controller.close()
                if let window = NSApp.windows.first(where: { $0.identifier == MainWindowMarker.identifier }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
                NSApp.activate()
            }
            Divider()
            Button("Çıkış") { NSApp.terminate(nil) }
        }
    }
#endif
