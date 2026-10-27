#if os(macOS)
    import AppKit
    import SwiftUI

    /// A context menu for a view SwiftUI's `.contextMenu` never shows — a tab in the window toolbar (ISSUE-191,
    /// ISSUE-264). The toolbar hands no right click down to an item's views: neither SwiftUI's menu nor an AppKit
    /// view's own `menu(for:)` under the tab ever saw one. So this view watches the window's presses itself: a local
    /// event monitor sees a right click or a control-click before the toolbar does and, where it lands on this view,
    /// pops the menu built from `sections` at that moment — its items say what the tab can do now. Every other event
    /// passes the view by (nothing is ever hit here).
    struct ContextMenuOverlay: NSViewRepresentable {
        struct Item {
            var title: String
            /// An SF Symbol beside the title.
            var symbol: String?
            var enabled = true
            /// The item's accessibility identifier (UI tests look menu items up by it).
            var identifier: String?
            var action: () -> Void
        }

        /// The menu's sections (a separator between them), asked for as the menu opens.
        let sections: () -> [[Item]]

        func makeNSView(context: Context) -> MenuView {
            let view = MenuView()
            view.sections = sections
            return view
        }

        func updateNSView(_ view: MenuView, context: Context) {
            view.sections = sections
        }

        static func dismantleNSView(_ view: MenuView, coordinator: ()) { view.stop() }

        final class MenuView: NSView {
            var sections: () -> [[Item]] = { [] }
            private var monitor: Any?

            /// Clicks, drags and hovers reach the view below; the menu press is taken by the monitor.
            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stop()
                guard window != nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                    let taken = MainActor.assumeIsolated { self?.take(event) ?? false }
                    return taken ? nil : event
                }
            }

            func stop() {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }

            /// Whether the press is this view's menu: a right click or control-click in its window, on it, with
            /// something to show — then the menu pops and the press goes no further.
            private func take(_ event: NSEvent) -> Bool {
                guard Self.opensMenu(event), let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                    bounds.contains(convert(event.locationInWindow, from: nil))
                else { return false }
                let menu = Self.menu(sections())
                guard !menu.items.isEmpty else { return false }
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return true
            }

            /// A right click, or a control-click.
            static func opensMenu(_ event: NSEvent) -> Bool {
                event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            }

            /// The sections as one menu: a separator between sections that have items, each item's action kept
            /// alive by the item itself.
            static func menu(_ sections: [[Item]]) -> NSMenu {
                let menu = NSMenu()
                menu.autoenablesItems = false
                for section in sections where !section.isEmpty {
                    if !menu.items.isEmpty { menu.addItem(.separator()) }
                    for item in section {
                        let action = MenuAction(item.action)
                        let entry = NSMenuItem(title: item.title, action: #selector(MenuAction.fire), keyEquivalent: "")
                        entry.target = action
                        entry.representedObject = action
                        entry.isEnabled = item.enabled
                        if let symbol = item.symbol {
                            entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                        }
                        if let identifier = item.identifier {
                            entry.identifier = NSUserInterfaceItemIdentifier(identifier)
                        }
                        menu.addItem(entry)
                    }
                }
                return menu
            }
        }

        /// An item's action as a menu item's target.
        final class MenuAction: NSObject {
            let action: () -> Void

            init(_ action: @escaping () -> Void) { self.action = action }

            @objc func fire() { action() }
        }
    }
#endif
