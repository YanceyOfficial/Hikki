import SwiftUI

#if os(macOS)
    import AppKit
#endif

extension View {
    /// A tooltip that belongs to this view alone. Inside a window toolbar item, SwiftUI lifts the first `.help` up to
    /// the whole item (every tab showed the first tab's title); an AppKit tooltip on the view's own frame doesn't move.
    /// The tooltip view takes no clicks. iOS and iPadOS use `.help`.
    public func toolTip(_ text: String) -> some View {
        #if os(macOS)
            overlay(ToolTipArea(text: text))
        #else
            help(text)
        #endif
    }
}

#if os(macOS)
    private struct ToolTipArea: NSViewRepresentable {
        let text: String

        func makeNSView(context: Context) -> PassThroughView {
            let view = PassThroughView()
            view.toolTip = text
            return view
        }

        func updateNSView(_ view: PassThroughView, context: Context) {
            if view.toolTip != text { view.toolTip = text }
        }
    }

    /// Holds a tooltip rect; clicks and drags go to whatever is under it.
    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
#endif

#Preview {
    HStack {
        Text(verbatim: "Hover me").padding().background(Theme.muted).toolTip("A tooltip of its own")
        Text(verbatim: "And me").padding().background(Theme.muted).toolTip("Another one")
    }
    .padding()
}
