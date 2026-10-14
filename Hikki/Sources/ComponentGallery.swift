#if DEBUG
    import HikkiUI
    import SwiftUI

    /// DEBUG-only visual check of every HikkiUI component in one screen.
    /// Launch with the `-HikkiGallery` argument (Xcode: Edit Scheme → Arguments), or use the per-file `#Preview`s.
    enum ComponentGalleryLaunch {
        static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-HikkiGallery") }
    }

    struct ComponentGalleryView: View {
        @State private var active: Set<String> = ["bold"]

        var body: some View {
            NavigationStack {
                List {
                    Section("ToolbarIconButton") {
                        HStack {
                            ForEach(EditorCommand.allCases.prefix(6)) { command in
                                ToolbarIconButton(
                                    LocalizedStringKey(command.title), symbol: command.icon,
                                    isActive: active.contains(command.rawValue)
                                ) {
                                    active.formSymmetricDifference([command.rawValue])
                                }
                            }
                        }
                    }
                    Section("KeyboardDismissButton") {
                        KeyboardDismissButton {}
                    }
                    Section("KeyboardAccessoryBar") {
                        KeyboardAccessoryBar(onDismiss: {}) {
                            ForEach(EditorCommand.allCases) { command in
                                ToolbarIconButton(
                                    LocalizedStringKey(command.title), symbol: command.icon,
                                    isActive: active.contains(command.rawValue)
                                ) {
                                    active.formSymmetricDifference([command.rawValue])
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    }
                    Section("SearchResultRow") {
                        SearchResultRow(
                            title: "Weekly sync", icon: "🗓️", path: "Work / Meetings", terms: ["week"], updatedAt: .now,
                            isSelected: true)
                        SearchResultRow(
                            title: "Roadmap", icon: nil, snippet: "…the roadmap is due Friday, after the review…",
                            path: "Projects", terms: ["roadmap", "friday"], updatedAt: .now.addingTimeInterval(-3 * 86_400))
                        SearchResultRow(
                            title: "Trip", icon: "🧭", snippet: "…BOARDING PASS · gate B12…", terms: ["gate"],
                            attachment: "boarding-pass.pdf", updatedAt: .now.addingTimeInterval(-86_400))
                    }
                }
                .navigationTitle("HikkiUI Gallery")
            }
        }
    }
#endif
