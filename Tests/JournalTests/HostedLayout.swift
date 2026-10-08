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

        /// Keeps a view mounted offscreen so a test can reach the AppKit controls SwiftUI made for
        /// it and watch them follow state. The window is never ordered on screen.
        @MainActor
        final class Mount {
            let window: NSWindow
            private let host: NSView

            init<V: View>(_ view: V, size: CGSize) {
                let hosting = NSHostingView(rootView: view)
                hosting.sizingOptions = []
                hosting.sceneBridgingOptions = [.title]
                hosting.frame = NSRect(origin: .zero, size: size)
                window = NSWindow(
                    contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                    styleMask: [.titled],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                host = hosting
            }

            /// Lets SwiftUI run its pending updates and lay the tree out again.
            func settle(rounds: Int = 6) async {
                host.needsLayout = true
                host.layoutSubtreeIfNeeded()
                for _ in 0..<rounds {
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(30))
                    host.layoutSubtreeIfNeeded()
                }
            }

            /// Every view of this type under the hosted root, in tree order.
            func views<T: NSView>(_ type: T.Type) -> [T] {
                var found: [T] = []
                func walk(_ view: NSView) {
                    if let match = view as? T { found.append(match) }
                    view.subviews.forEach(walk)
                }
                walk(host)
                return found
            }

            func close() {
                window.contentView = nil
            }
        }
    }
#endif
