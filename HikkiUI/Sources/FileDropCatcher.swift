#if os(macOS)
    import AppKit
    import SwiftUI

    /// Takes drops meant for a card whose text field would take them itself (the AI chat's composer, ISSUE-197). A
    /// SwiftUI `.onDrop` is no AppKit view: AppKit hands a drag to the deepest view registered for its types, which
    /// over the field is its text view — and that types a dropped file's path. This view lies over the card, above
    /// the field, registered for the pasteboard types it is given, so for those it is that deepest view; a click
    /// never meets it (`hitTest` nil). `accepts` says whether what is on the pasteboard is wanted, `onDrop` takes
    /// it, and `onTargeted` follows the drag for the card's outline.
    public struct FileDropCatcher: NSViewRepresentable {
        let types: [NSPasteboard.PasteboardType]
        let accepts: (NSPasteboard) -> Bool
        let onTargeted: (Bool) -> Void
        let onDrop: (NSPasteboard) -> Void

        /// - Parameters:
        ///   - types: the pasteboard types to take (the field keeps every other drop: text).
        ///   - accepts: whether a drag's pasteboard holds something wanted (its types alone don't say).
        ///   - onTargeted: the drag is over the view with something wanted / has left or landed.
        ///   - onDrop: the drop, with its pasteboard.
        public init(
            types: [NSPasteboard.PasteboardType], accepts: @escaping (NSPasteboard) -> Bool,
            onTargeted: @escaping (Bool) -> Void, onDrop: @escaping (NSPasteboard) -> Void
        ) {
            self.types = types
            self.accepts = accepts
            self.onTargeted = onTargeted
            self.onDrop = onDrop
        }

        public func makeNSView(context: Context) -> CatcherView {
            let view = CatcherView()
            view.registerForDraggedTypes(types)
            updateNSView(view, context: context)
            return view
        }

        public func updateNSView(_ view: CatcherView, context: Context) {
            view.accepts = accepts
            view.onTargeted = onTargeted
            view.onDrop = onDrop
            view.raise()
        }

        public final class CatcherView: NSView {
            var accepts: (NSPasteboard) -> Bool = { _ in false }
            var onTargeted: (Bool) -> Void = { _ in }
            var onDrop: (NSPasteboard) -> Void = { _ in }

            public override func hitTest(_ point: NSPoint) -> NSView? { nil }

            public override func viewDidMoveToSuperview() {
                super.viewDidMoveToSuperview()
                raise()
            }

            /// Last among its siblings, so AppKit asks it before the field's view (the deepest match wins, siblings
            /// from the last); SwiftUI keeps its platform views in its own order, which this view steps out of.
            func raise() {
                guard let superview, superview.subviews.last !== self else { return }
                superview.addSubview(self, positioned: .above, relativeTo: nil)
            }

            public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
                guard accepts(sender.draggingPasteboard) else { return [] }
                onTargeted(true)
                return .copy
            }

            public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
                accepts(sender.draggingPasteboard) ? .copy : []
            }

            public override func draggingExited(_ sender: (any NSDraggingInfo)?) { onTargeted(false) }

            public override func draggingEnded(_ sender: any NSDraggingInfo) { onTargeted(false) }

            public override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
                accepts(sender.draggingPasteboard)
            }

            public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
                onTargeted(false)
                guard accepts(sender.draggingPasteboard) else { return false }
                onDrop(sender.draggingPasteboard)
                return true
            }
        }
    }
#endif
