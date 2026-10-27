#if os(macOS)
    import AppKit
    import Testing

    @testable import HikkiUI

    /// A drag as AppKit describes it to a destination: only the pasteboard matters here.
    private nonisolated final class FakeDrag: NSObject, NSDraggingInfo {
        let pasteboard: NSPasteboard

        init(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

        var draggingPasteboard: NSPasteboard { pasteboard }
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggingLocation: NSPoint { .zero }
        var draggedImageLocation: NSPoint { .zero }
        var draggedImage: NSImage? { nil }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 0 }
        var numberOfValidItemsForDrop = 1
        var draggingFormation = NSDraggingFormation.default
        var animatesToDestination = false
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        func resetSpringLoading() {}
        func enumerateDraggingItems(
            options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
            searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
            using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
        ) {}
    }

    @MainActor
    struct FileDropCatcherTests {
        private func pasteboard(_ objects: [NSPasteboardWriting]) -> NSPasteboard {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("hikki-test-\(UUID().uuidString)"))
            pasteboard.clearContents()
            pasteboard.writeObjects(objects)
            return pasteboard
        }

        private func catcher(onTargeted: @escaping (Bool) -> Void = { _ in }, onDrop: @escaping (NSPasteboard) -> Void = { _ in })
            -> FileDropCatcher.CatcherView
        {
            let view = FileDropCatcher.CatcherView()
            view.registerForDraggedTypes([.fileURL])
            view.accepts = { $0.types?.contains(.fileURL) == true }
            view.onTargeted = onTargeted
            view.onDrop = onDrop
            return view
        }

        /// A dropped file is taken (ISSUE-197: the field under the card typed its path); a click is never taken.
        @Test func aFileDropIsTakenAndAClickFallsThrough() {
            var targeted: [Bool] = []
            var dropped: [NSPasteboard] = []
            let view = catcher(onTargeted: { targeted.append($0) }, onDrop: { dropped.append($0) })
            #expect(view.registeredDraggedTypes.contains(.fileURL))
            #expect(view.hitTest(.zero) == nil)

            let file = pasteboard([URL(fileURLWithPath: "/tmp/photo.png") as NSURL])
            let drag = FakeDrag(file)
            #expect(view.draggingEntered(drag) == .copy)
            #expect(view.prepareForDragOperation(drag))
            #expect(view.performDragOperation(drag))
            #expect(dropped.count == 1)
            #expect(dropped.first === file)
            #expect(targeted == [true, false])
        }

        @Test func textIsLeftToTheField() {
            var dropped = 0
            let view = catcher(onDrop: { _ in dropped += 1 })
            let drag = FakeDrag(pasteboard(["just words" as NSString]))
            #expect(view.draggingEntered(drag) == [])
            #expect(!view.performDragOperation(drag))
            #expect(dropped == 0)
        }
    }
#endif
