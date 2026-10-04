#if os(macOS)
    import AppKit
    import SwiftUI

    /// Consume wheel events only over this canvas, leaving surrounding scroll views alone.
    struct GraphScrollZoom: NSViewRepresentable {
        let onScroll: (Double) -> Void
        final class Coordinator {
            var monitor: Any?
            var action: (Double) -> Void
            init(action: @escaping (Double) -> Void) { self.action = action }
        }
        func makeCoordinator() -> Coordinator { Coordinator(action: onScroll) }
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            let coordinator = context.coordinator
            coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak view, weak coordinator] event in
                let consumed = MainActor.assumeIsolated {
                    guard let view, let coordinator, let window = view.window, !view.isHiddenOrHasHiddenAncestor,
                        event.window === window,
                        view.bounds.contains(view.convert(event.locationInWindow, from: nil))
                    else { return false }
                    coordinator.action(event.scrollingDeltaY)
                    return true
                }
                return consumed ? nil : event
            }
            return view
        }
        func updateNSView(_ view: NSView, context: Context) { context.coordinator.action = onScroll }
        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
            if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
            coordinator.monitor = nil
        }
    }
#endif
