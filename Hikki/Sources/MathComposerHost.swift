#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The iPhone's formula editor (HikkiUI's `MathComposer`, the `mathSheet` request) over the page: what is typed
    /// shows in the page meanwhile (`previewMath`), and the card answers once — Done keeps the formula as typed, Cancel
    /// puts it back as it was, Remove Formula takes it out — then goes.
    struct MathComposerHost: View {
        let request: EditorController.MathRequest
        let editor: EditorController
        @State private var answered = false

        var body: some View {
            MathComposer(
                latex: request.latex, kind: request.kind == .inline ? .inline : .block,
                onChange: { editor.previewMath($0, id: request.id) },
                onDone: { answer($0) },
                onCancel: { answer(nil) },
                onRemove: { answer("") }
            )
            // Taken down otherwise (the page left): the formula goes back as it was.
            .onDisappear { answer(nil) }
        }

        /// The one answer an opening gets: the formula's text (empty: removed), or nil for Cancel.
        private func answer(_ text: String?) {
            guard !answered else { return }
            answered = true
            let id = request.id
            Task { await editor.applyMath(text, id: id) }
            editor.closeMathSheet()
        }
    }
#endif
