#if os(macOS)
    import AppKit
    import Testing

    @testable import HikkiUI

    @MainActor
    struct ContextMenuOverlayTests {
        private func press(_ type: NSEvent.EventType, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        /// A right click or a control-click opens the menu; every other press falls through to the tab (ISSUE-191).
        @Test func onlyAMenuPressIsTaken() {
            #expect(ContextMenuOverlay.MenuView.opensMenu(press(.rightMouseDown)))
            #expect(ContextMenuOverlay.MenuView.opensMenu(press(.leftMouseDown, flags: .control)))
            #expect(!ContextMenuOverlay.MenuView.opensMenu(press(.leftMouseDown)))
            #expect(!ContextMenuOverlay.MenuView.opensMenu(press(.leftMouseDown, flags: .command)))
            #expect(!ContextMenuOverlay.MenuView.opensMenu(press(.mouseMoved)))
        }

        @Test func theMenuHasTheSectionsItemsWithSeparatorsBetween() {
            var ran: [String] = []
            let menu = ContextMenuOverlay.MenuView.menu([
                [
                    .init(title: "New Tab to the Right", symbol: "plus", identifier: "tab-menu-newToRight") { ran.append("new") },
                    .init(title: "Duplicate", symbol: nil) { ran.append("dup") },
                ],
                [],
                [.init(title: "Close", symbol: nil, enabled: false) { ran.append("close") }],
            ])
            #expect(menu.items.map(\.title) == ["New Tab to the Right", "Duplicate", "", "Close"])
            #expect(menu.items[2].isSeparatorItem)
            #expect(menu.items[0].identifier?.rawValue == "tab-menu-newToRight")
            #expect(menu.items[0].image != nil)
            #expect(menu.items[1].image == nil)
            #expect(!menu.autoenablesItems)
            #expect(menu.items[3].isEnabled == false)
            // The item runs its action (kept alive by the item itself).
            _ = (menu.items[1].target as? NSObject)?.perform(menu.items[1].action!)
            #expect(ran == ["dup"])
        }
    }
#endif
