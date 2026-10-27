#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The iPhone's find bar (HikkiUI's `FindBar`) over the page: the page reports the search (`findState`) and the bar
    /// drives it — the term and the replacement as typed, the options, ‹ ›, Replace / Replace All, Done. The bar keeps its
    /// own typing; the state it opened with gives the first term (the page's selection), the counts follow the page.
    struct FindBarHost: View {
        let state: FindState
        let editor: EditorController
        /// False on a locked page: Replace stays out of the options.
        let canReplace: Bool
        @State private var term: String
        @State private var replaceTerm: String
        @State private var options: FindBarOptions

        init(state: FindState, editor: EditorController, canReplace: Bool) {
            self.state = state
            self.editor = editor
            self.canReplace = canReplace
            _term = State(initialValue: state.term)
            _replaceTerm = State(initialValue: state.replaceTerm)
            _options = State(
                initialValue: FindBarOptions(
                    replace: state.replace, caseSensitive: state.caseSensitive, wholeWord: state.wholeWord, regex: state.regex))
        }

        var body: some View {
            FindBar(
                term: $term, replaceTerm: $replaceTerm, options: $options,
                status: FindBarStatus(count: state.count, current: state.current), canReplace: canReplace,
                onStep: { editor.findStep($0) }, onReplace: { editor.findReplace(all: $0) }, onClose: { editor.closeFind() }
            )
            .onChange(of: term) { editor.findSet(term: term) }
            .onChange(of: replaceTerm) { editor.findSet(replaceTerm: replaceTerm) }
            .onChange(of: options) {
                editor.findSet(
                    caseSensitive: options.caseSensitive, wholeWord: options.wholeWord, regex: options.regex,
                    replace: options.replace)
            }
        }
    }
#endif
