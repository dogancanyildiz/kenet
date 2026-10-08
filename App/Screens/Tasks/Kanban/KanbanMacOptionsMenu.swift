import SwiftUI

#if os(macOS)
    import AppKit

    /// "Pano seçenekleri" as a content-sized menu that stays inside the window.
    ///
    /// The shared header menu uses a button-style ``Menu``. On Mac that popup grows to the right
    /// of the trailing icon and leaves the window. AppKit's `popUp` is placed so the menu's right
    /// edge sits on the icon (it grows left). The popup is scheduled for the next turn so a UI
    /// test's click can return while the menu is still open.
    struct KanbanMacOptionsMenu: NSViewRepresentable {
        @Binding var showsCancelled: Bool

        func makeCoordinator() -> Coordinator {
            Coordinator(showsCancelled: $showsCancelled)
        }

        func makeNSView(context: Context) -> NSButton {
            let button = NSButton()
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.target = context.coordinator
            button.action = #selector(Coordinator.showMenu(_:))
            button.setAccessibilityElement(true)
            button.setAccessibilityRole(.button)
            button.setAccessibilityIdentifier("tasks.kanban.options")
            button.setAccessibilityLabel(String(localized: "Pano seçenekleri"))
            button.toolTip = String(localized: "Pano seçenekleri")
            return button
        }

        func updateNSView(_ button: NSButton, context: Context) {
            context.coordinator.showsCancelled = $showsCancelled
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            button.image = NSImage(
                systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil
            )?
            .withSymbolConfiguration(config)
            button.contentTintColor = NSColor(
                InkButtonChrome.color(
                    for: InkHeaderActionChrome.token(role: .utility, isActive: showsCancelled)))
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
            CGSize(width: 20, height: 20)
        }

        @MainActor
        final class Coordinator: NSObject {
            var showsCancelled: Binding<Bool>

            init(showsCancelled: Binding<Bool>) {
                self.showsCancelled = showsCancelled
            }

            @objc func showMenu(_ sender: NSButton) {
                let menu = NSMenu()
                menu.autoenablesItems = false
                let item = NSMenuItem(
                    title: String(localized: "İptal edilenleri göster"),
                    action: #selector(toggleCancelled(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.state = showsCancelled.wrappedValue ? .on : .off
                menu.addItem(item)
                DispatchQueue.main.async { [weak sender] in
                    guard let sender else { return }
                    menu.update()
                    let measured = menu.size.width
                    let menuWidth = measured > 40 ? measured : KanbanOptionsMenuLayout.reservedLabelWidth
                    let originX = KanbanOptionsMenuLayout.menuOriginX(
                        menuWidth: menuWidth,
                        anchorMaxX: sender.bounds.maxX,
                        limitX: sender.bounds.maxX,
                        minimumX: -10_000
                    )
                    menu.popUp(
                        positioning: nil, at: NSPoint(x: originX, y: sender.bounds.minY), in: sender)
                }
            }

            @objc func toggleCancelled(_ sender: NSMenuItem) {
                showsCancelled.wrappedValue.toggle()
            }
        }
    }
#endif
