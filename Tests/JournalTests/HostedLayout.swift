#if os(macOS)
    import AppKit
    import SwiftUI

    /// Lays a SwiftUI view out offscreen so a test can read a preference from the real frames.
    /// The window is never ordered on screen.
    @MainActor
    enum HostedLayout {
        final class Sink {
            var values: [CGFloat] = []
        }

        static func settle<V: View>(_ view: V, size: CGSize) async {
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = host
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            for _ in 0..<8 {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(30))
                host.layoutSubtreeIfNeeded()
            }
            window.contentView = nil
        }
    }
#endif
