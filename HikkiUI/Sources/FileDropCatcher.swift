#if os(macOS)
    import AppKit
    import SwiftUI

    /// Takes drops meant for a card whose text field would take them itself (the AI chat's composer, ISSUE-197,
    /// ISSUE-263). A SwiftUI `.onDrop` is no AppKit view: AppKit hands a drag to the deepest view registered for its
    /// types, which over the field is its text view — and that types a dropped file's path. Two things keep the drop
    /// from it: this view lies over the card, above the field, registered for the pasteboard types it is given, so
    /// for those it is that deepest view; and the text views under it are left registered for text alone
    /// (`quietTextViews`), so a file or a picture falls through to this view whichever AppKit asks first. A click
    /// never meets it (`hitTest` nil). `accepts` says whether what is on the pasteboard is wanted, `onDrop` takes it,
    /// `onTargeted` follows the drag for the card's outline, and `trace` gets a line per step for the log.
    public struct FileDropCatcher: NSViewRepresentable {
        let types: [NSPasteboard.PasteboardType]
        let accepts: (NSPasteboard) -> Bool
        let onTargeted: (Bool) -> Void
        let onDrop: (NSPasteboard) -> Void
        let trace: ((String) -> Void)?

        /// - Parameters:
        ///   - types: the pasteboard types to take (the field keeps every other drop: text).
        ///   - accepts: whether a drag's pasteboard holds something wanted (its types alone don't say).
        ///   - onTargeted: the drag is over the view with something wanted / has left or landed.
        ///   - onDrop: the drop, with its pasteboard.
        ///   - trace: a line per step — types and view classes, never content — for the app's log.
        public init(
            types: [NSPasteboard.PasteboardType], accepts: @escaping (NSPasteboard) -> Bool,
            onTargeted: @escaping (Bool) -> Void, onDrop: @escaping (NSPasteboard) -> Void,
            trace: ((String) -> Void)? = nil
        ) {
            self.types = types
            self.accepts = accepts
            self.onTargeted = onTargeted
            self.onDrop = onDrop
            self.trace = trace
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
            view.trace = trace
            view.raise()
            view.quietTextViews()
        }

        public static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.stopObserving() }

        /// The whole of what it is laid over, never an intrinsic size of its own.
        public func sizeThatFits(_ proposal: ProposedViewSize, nsView: CatcherView, context: Context) -> CGSize? {
            CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
        }

        public final class CatcherView: NSView {
            var accepts: (NSPasteboard) -> Bool = { _ in false }
            var onTargeted: (Bool) -> Void = { _ in }
            var onDrop: (NSPasteboard) -> Void = { _ in }
            var trace: ((String) -> Void)?
            private var observers: [any NSObjectProtocol] = []
            private var reported = false

            public override func hitTest(_ point: NSPoint) -> NSView? { nil }

            public override func viewDidMoveToSuperview() {
                super.viewDidMoveToSuperview()
                raise()
            }

            public override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                stopObserving()
                guard window != nil else { return }
                // A text field's editor is installed as editing begins, registered for every type again.
                for name in [NSControl.textDidBeginEditingNotification, NSText.didBeginEditingNotification] {
                    observers.append(
                        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                            MainActor.assumeIsolated { self?.quietTextViews() }
                        })
                }
                quietTextViews()
            }

            public override func layout() {
                super.layout()
                quietTextViews()
            }

            func stopObserving() {
                for observer in observers { NotificationCenter.default.removeObserver(observer) }
                observers = []
            }

            /// Last among its siblings, so AppKit asks it before the field's view (the deepest match wins, siblings
            /// from the last); SwiftUI keeps its platform views in its own order, which this view steps out of.
            func raise() {
                guard let superview, superview.subviews.last !== self else { return }
                superview.addSubview(self, positioned: .above, relativeTo: nil)
            }

            /// The text views under this view — the composer's field, its field editor once it edits — are left
            /// registered for text alone: with every type AppKit gives them (files, pictures) they typed a dropped
            /// file's path, and AppKit may ask them before this view.
            func quietTextViews() {
                guard let root = window?.contentView ?? superview else { return }
                let mine = convert(bounds, to: nil)
                guard !mine.isEmpty else { return }
                var found: [NSView] = []
                Self.walk(root) { view in
                    guard view !== self, view is NSTextView || view is NSTextField else { return }
                    if view.convert(view.bounds, to: nil).intersects(mine) { found.append(view) }
                }
                for view in found {
                    let types = view.registeredDraggedTypes
                    guard types != [.string] else { continue }
                    view.unregisterDraggedTypes()
                    view.registerForDraggedTypes([.string])
                    trace?("drop: \(type(of: view)) took \(types.count) drag types, now text alone")
                }
                if !reported {
                    reported = true
                    let index = superview?.subviews.firstIndex { $0 === self } ?? -1
                    let chain = sequence(first: superview) { $0?.superview }.prefix(5).compactMap { $0 }
                        .map { String(describing: type(of: $0)) }.joined(separator: " < ")
                    trace?(
                        "drop: catcher \(Int(mine.width))×\(Int(mine.height)) over \(found.count) text view(s), sibling "
                            + "\(index + 1) of \(superview?.subviews.count ?? 0), under \(chain)")
                }
            }

            private static func walk(_ view: NSView, _ visit: (NSView) -> Void) {
                visit(view)
                for subview in view.subviews { walk(subview, visit) }
            }

            private func describe(_ pasteboard: NSPasteboard) -> String {
                (pasteboard.types ?? []).prefix(6).map(\.rawValue).joined(separator: " ")
            }

            public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
                let wanted = accepts(sender.draggingPasteboard)
                trace?("drop: entered, \(wanted ? "wanted" : "not wanted"): \(describe(sender.draggingPasteboard))")
                guard wanted else { return [] }
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
                trace?("drop: taken")
                onDrop(sender.draggingPasteboard)
                return true
            }
        }
    }
#endif
