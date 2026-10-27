#if os(macOS)
    import AppKit
    import SwiftUI

    /// A context menu for a view SwiftUI's `.contextMenu` never shows — a tab in the window toolbar, where the press
    /// never reached SwiftUI's menu, with the tab's drag on it or without (ISSUE-191): an AppKit view laid over the
    /// content that is hit by a right click or a control-click alone — every other event falls through to what is
    /// under it — and pops the menu built from `sections` at that moment, so its items say what the tab can do now.
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

        final class MenuView: NSView {
            var sections: () -> [[Item]] = { [] }

            /// Only a press that opens a menu lands here; clicks, drags and hovers reach the view below.
            override func hitTest(_ point: NSPoint) -> NSView? {
                guard let event = NSApp.currentEvent, Self.opensMenu(event) else { return nil }
                return super.hitTest(point)
            }

            override func menu(for event: NSEvent) -> NSMenu? { Self.menu(sections()) }

            /// A control-click arrives as a left press; AppKit pops a menu only for a right one.
            override func mouseDown(with event: NSEvent) {
                guard event.modifierFlags.contains(.control), let menu = menu(for: event) else {
                    return super.mouseDown(with: event)
                }
                NSMenu.popUpContextMenu(menu, with: event, for: self)
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
