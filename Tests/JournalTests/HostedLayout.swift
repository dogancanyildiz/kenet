#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing

    /// Ends the test process when one hosted test keeps the main thread for too long, naming the
    /// test on standard error. A hosted test can block inside AppKit (a tracking loop, a modal
    /// session) where Swift Testing's time limit cannot cancel it; on a headless CI machine that
    /// was a job running into its 30 minute limit with no output. A crash is reported per test.
    ///
    /// A suite keeps one as a stored property: it starts with the suite instance (one per test)
    /// and stops when the instance goes away.
    final class HostedTestWatchdog: @unchecked Sendable {
        private let timer: DispatchSourceTimer

        init(seconds: Int = 120, test: String = Test.current?.name ?? "?") {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + .seconds(seconds))
            timer.setEventHandler {
                let line = "ASILDI: \(test) \(seconds) saniyede bitmedi; test süreci sonlandırılıyor\n"
                FileHandle.standardError.write(Data(line.utf8))
                abort()
            }
            timer.resume()
            self.timer = timer
        }

        deinit { timer.cancel() }
    }

    /// Focus tests need a window that hands out its first responder. A machine without a window
    /// server session may refuse; then the test has nothing to measure and returns early with a
    /// note instead of failing on the environment (the Mac screen tour covers the same ground).
    @MainActor
    enum HostedFocus {
        static func isAvailable(for view: NSView, in window: NSWindow, test: String = #function) -> Bool {
            if window.makeFirstResponder(view), let responder = window.firstResponder as? NSView,
                responder === view || responder.isDescendant(of: view) || (responder as? NSText)?.delegate === view
            {
                return true
            }
            let line = "ATLANDI (ortam odak vermiyor): \(test)\n"
            FileHandle.standardError.write(Data(line.utf8))
            return false
        }
    }

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

            /// `bridgesToolbar`: the window also receives the SwiftUI toolbar, so a test can read
            /// the toolbar items the view really installs.
            init<V: View>(_ view: V, size: CGSize, bridgesToolbar: Bool = false) {
                let hosting = NSHostingView(rootView: view)
                hosting.sizingOptions = []
                hosting.sceneBridgingOptions = bridgesToolbar ? [.title, .toolbars] : [.title]
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
