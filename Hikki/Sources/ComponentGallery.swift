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
        @State private var recording = false
        @State private var recorded = "⌘B"
        @State private var drawerOpen = true

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
                    Section("ShortcutRecorder") {
                        LabeledContent("Bold") {
                            ShortcutRecorder(
                                display: recorded, isCustom: recorded != "⌘B", recording: $recording,
                                identifier: "gallery-shortcut",
                                onRecord: { key, _ in recorded = "⌘" + String(key.character).uppercased() },
                                onReset: { recorded = "⌘B" })
                        }
                    }
                    Section("DropTargetArea") {
                        DropTargetArea("Drag a page here", icon: .trayArrowDown, isTargeted: false).frame(height: 80)
                        DropTargetArea("Show here", isTargeted: true).frame(height: 80)
                    }
                    Section("WeekActivityCard") {
                        WeekActivityCard(
                            title: "app:home.thisWeek", headline: "2,481", caption: "words written",
                            days: (0..<7).map {
                                .init(id: $0, label: "MTWTFSS".map(String.init)[$0], value: [1, 0, 8, 3, 0, 12, 0][$0], isToday: $0 == 5)
                            },
                            footnote: "32 pages · 41,203 words in all")
                    }
                    Section("ToastView") {
                        ToastView(kind: .success, message: "Link copied", close: {})
                        ToastView(
                            kind: .error, message: "Couldn't save the page.", reference: "HK-2001 · W7RM2D",
                            actionTitle: "app:toast.copyDetails", action: {}, close: {})
                    }
                    Section("FilterChip") {
                        HStack(spacing: Spacing.s1_5) {
                            FilterChip("All", isSelected: true) {}
                            FilterChip("Titles", isSelected: false) {}
                        }
                        HStack(spacing: Spacing.s2) {
                            FilterChip("All", isSelected: true, look: .filled) {}
                            FilterChip("Files", isSelected: false, look: .filled) {}
                        }
                    }
                    Section("ModelPickerList") {
                        ModelPickerList(
                            autoID: "auto", autoTitle: "Auto",
                            groups: [
                                .init(id: "f", title: "Favorites", items: [.init(id: "o", name: "Opus 5.5", isFavorite: true)]),
                                .init(id: "r", title: "Recommended", items: [.init(id: "s", name: "Sonnet 5.5", detail: "Anthropic")]),
                            ],
                            selection: "s", onSelect: { _ in }, onToggleFavorite: { _ in })
                    }
                    Section("toolTip") {
                        HStack {
                            Text(verbatim: "Hover").padding(Spacing.s2).background(Theme.muted).toolTip("Its own tooltip")
                            Text(verbatim: "Me too").padding(Spacing.s2).background(Theme.muted).toolTip("Another one")
                        }
                    }
                    Section("ThumbnailOption + ReviewStyleThumbnail") {
                        HStack(alignment: .top, spacing: Spacing.s2) {
                            ForEach(ReviewStyleThumbnail.Sketch.allCases, id: \.self) { sketch in
                                ThumbnailOption(LocalizedStringKey(sketch.rawValue), isSelected: sketch == .inline, action: {}) {
                                    ReviewStyleThumbnail(sketch)
                                }
                            }
                        }
                    }
                    Section("FloatingActionBar") {
                        FloatingActionBar(
                            leading: .init("Search", icon: .magnifyingGlass, identifier: "gallery-search") {}, prompt: "Ask AI",
                            promptIdentifier: "gallery-ask", onPrompt: {},
                            trailing: .init("New page", icon: .notePencil, identifier: "gallery-new") {})
                    }
                    #if os(iOS)
                        Section("SideDrawer") {
                            SideDrawer(isOpen: $drawerOpen, closeLabel: "Close sidebar") {
                                VStack(alignment: .leading, spacing: Spacing.s2) {
                                    Text(verbatim: "Workspace").font(.hk(.base, .semibold))
                                    Text(verbatim: "Getting started")
                                    Text(verbatim: "Reading list")
                                }
                                .padding(Spacing.s3)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            } content: {
                                Button {
                                    withAnimation(Motion.easeOut()) { drawerOpen.toggle() }
                                } label: {
                                    IconView(.list, size: TextSize.xl.rawValue)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(Spacing.s3)
                            }
                            .frame(height: 240)
                            .listRowInsets(EdgeInsets())
                        }
                    #endif
                    Section("AIGlyph") {
                        HStack(spacing: Spacing.s4) {
                            AIGlyph()
                            AIGlyph(size: 24)
                        }
                    }
                    Section("VersionDiffView") {
                        VersionTitleView(
                            title: "Trip to Kyoto", runs: [.init("Trip to ", .same), .init("Osaka", .removed), .init("Kyoto", .added)],
                            placeholder: "Untitled")
                        VersionDiffView(blocks: [
                            .init(id: 0, style: .heading2, runs: [.init("Plan", .same)]),
                            .init(
                                id: 1, style: .paragraph,
                                runs: [.init("Leave on ", .same), .init("Friday", .removed), .init("Saturday", .added)]),
                            .init(id: 2, style: .bullet, change: .added, runs: [.init("Book the ryokan", .added)]),
                            .init(id: 3, style: .paragraph, change: .removed, runs: [.init("An old note", .removed)]),
                        ])
                    }
                    Section("TaskProgressRow") {
                        TaskProgressRow(Text(verbatim: "Importing 3 of 20"), done: 3, total: 20, cancelTitle: "Cancel") {}
                        TaskProgressRow(Text(verbatim: "Reading files…"), done: 0, total: 0, cancelTitle: "Cancel") {}
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
                    Section("SearchMatchRow · SearchMatchesToggleRow") {
                        SearchMatchRow(snippet: "雨が降っているので家にいます。", terms: ["ので"], isSelected: true)
                        SearchMatchRow(snippet: "日本語がわからないので、英語で話していただけませんか。", terms: ["ので"])
                        SearchMatchesToggleRow("12 more matches")
                        SearchMatchesToggleRow("Show fewer", isExpanded: true)
                    }
                }
                .navigationTitle("HikkiUI Gallery")
            }
        }
    }
#endif
