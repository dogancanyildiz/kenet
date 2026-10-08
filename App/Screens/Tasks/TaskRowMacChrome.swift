#if os(macOS)
    import AppKit
    import SwiftUI
    import VaultFormat

    /// Mac task-row menu. A SwiftUI context menu focuses the row and AppKit then draws a
    /// square ring past the list column, and it ignores `.destructive` on "Sil".
    /// This overlay takes only the right click, so the row does not become first responder.
    struct TaskRowMacChrome: NSViewRepresentable {
        var hasDue: Bool
        var editText: () -> Void
        var editDate: () -> Void
        var clearDate: () -> Void
        var editRecurrence: () -> Void
        var setPriority: (VaultFormat.TaskPriority?) -> Void
        var delete: () -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> TaskRowMacMenuView {
            let view = TaskRowMacMenuView()
            view.coordinator = context.coordinator
            return view
        }

        func updateNSView(_ nsView: TaskRowMacMenuView, context: Context) {
            let coordinator = context.coordinator
            coordinator.hasDue = hasDue
            coordinator.editText = editText
            coordinator.editDate = editDate
            coordinator.clearDate = clearDate
            coordinator.editRecurrence = editRecurrence
            coordinator.setPriority = setPriority
            coordinator.delete = delete
            nsView.coordinator = coordinator
        }

        final class Coordinator: NSObject {
            var hasDue = false
            var editText: () -> Void = {}
            var editDate: () -> Void = {}
            var clearDate: () -> Void = {}
            var editRecurrence: () -> Void = {}
            var setPriority: (VaultFormat.TaskPriority?) -> Void = { _ in }
            var delete: () -> Void = {}

            @objc func editTextItem() { editText() }
            @objc func editDateItem() { editDate() }
            @objc func clearDateItem() { clearDate() }
            @objc func editRecurrenceItem() { editRecurrence() }
            @objc func priorityHigh() { setPriority(.high) }
            @objc func priorityMedium() { setPriority(.medium) }
            @objc func priorityLow() { setPriority(.low) }
            @objc func priorityNone() { setPriority(nil) }
            @objc func deleteItem() { delete() }
        }
    }

    final class TaskRowMacMenuView: NSView {
        var coordinator: TaskRowMacChrome.Coordinator?

        override var isOpaque: Bool { false }
        override var acceptsFirstResponder: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point), wantsMenuEvent else { return nil }
            return self
        }

        override func rightMouseDown(with event: NSEvent) {
            showMenu(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                showMenu(with: event)
            } else {
                super.mouseDown(with: event)
            }
        }

        private var wantsMenuEvent: Bool {
            guard let event = window?.currentEvent ?? NSApp.currentEvent else { return false }
            if event.type == .rightMouseDown || event.type == .rightMouseUp { return true }
            return event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        }

        private func showMenu(with event: NSEvent) {
            guard let coordinator else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            add(menu, "Metni düzenle", #selector(TaskRowMacChrome.Coordinator.editTextItem), "pencil", coordinator)
            add(
                menu, "Tarih ver / değiştir", #selector(TaskRowMacChrome.Coordinator.editDateItem), "calendar",
                coordinator)
            if coordinator.hasDue {
                add(menu, "Tarihi kaldır", #selector(TaskRowMacChrome.Coordinator.clearDateItem), nil, coordinator)
            }
            add(menu, "Tekrar", #selector(TaskRowMacChrome.Coordinator.editRecurrenceItem), "repeat", coordinator)
            let priority = NSMenu()
            priority.autoenablesItems = false
            add(priority, "Yüksek", #selector(TaskRowMacChrome.Coordinator.priorityHigh), nil, coordinator)
            add(priority, "Orta", #selector(TaskRowMacChrome.Coordinator.priorityMedium), nil, coordinator)
            add(priority, "Düşük", #selector(TaskRowMacChrome.Coordinator.priorityLow), nil, coordinator)
            add(priority, "Yok", #selector(TaskRowMacChrome.Coordinator.priorityNone), nil, coordinator)
            let priorityItem = NSMenuItem(title: String(localized: "Öncelik"), action: nil, keyEquivalent: "")
            priorityItem.submenu = priority
            menu.addItem(priorityItem)
            menu.addItem(deleteItem(coordinator))
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        private func add(
            _ menu: NSMenu, _ title: String, _ action: Selector, _ symbol: String?, _ target: AnyObject
        ) {
            menu.addItem(item(title, action, symbol, target))
        }

        private func item(_ title: String, _ action: Selector, _ symbol: String?, _ target: AnyObject) -> NSMenuItem {
            let item = NSMenuItem(
                title: String(localized: String.LocalizationValue(title)), action: action, keyEquivalent: "")
            item.target = target
            if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title) {
                item.image = image
            }
            return item
        }

        private func deleteItem(_ target: AnyObject) -> NSMenuItem {
            let title = String(localized: "Sil")
            let item = NSMenuItem(
                title: title, action: #selector(TaskRowMacChrome.Coordinator.deleteItem), keyEquivalent: "")
            item.target = target
            let color = NSColor(named: NSColor.Name("InkDanger")) ?? .systemRed
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.menuFont(ofSize: 0),
                ])
            if let image = NSImage(systemSymbolName: "trash", accessibilityDescription: title) {
                item.image = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
            }
            return item
        }
    }
#endif
