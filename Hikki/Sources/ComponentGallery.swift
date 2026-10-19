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
        @State private var dialogPage = "general"
        private let galleryTabs = [UUID(), UUID()]
        private let galleryToasts = [GalleryToast(message: "Page duplicated"), GalleryToast(message: "Link copied")]

        private struct GalleryToast: Identifiable {
            let id = UUID()
            let message: String
        }

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
                    Section("KeyboardBlockPanel") {
                        KeyboardBlockPanel(
                            sections: [
                                .init(
                                    id: "basic", title: "Basic blocks",
                                    items: [
                                        .init(id: "paragraph", label: "Text", icon: .textT),
                                        .init(id: "heading1", label: "Heading 1", icon: .textHOne),
                                        .init(id: "bulletList", label: "Bulleted list", icon: .listBullets),
                                        .init(id: "taskList", label: "To-do list", icon: .checkSquare),
                                    ])
                            ], onPick: { _ in }
                        )
                        .frame(height: 160)
                    }
                    Section("KeyboardFormatPanel") {
                        KeyboardFormatPanel(
                            marks: [.bold], turnInto: [.init(id: "paragraph", label: "Text", icon: .textT)], block: "paragraph",
                            textColor: "red", backgroundColor: nil, onMark: { _ in }, onTurnInto: { _ in }, onColor: { _, _ in }
                        )
                        .frame(height: 320)
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
                    Section("SidebarDialog") {
                        SidebarDialog(
                            "Settings",
                            sections: [
                                .init(
                                    id: 0, title: "Workspace",
                                    items: [.init(id: "workspace", title: "Workspace", icon: .house, identifier: "w")]),
                                .init(
                                    id: 1, title: "App",
                                    items: [
                                        .init(id: "general", title: "General", icon: .gearSix, identifier: "g"),
                                        .init(id: "ai", title: "AI", icon: .sparkle, identifier: "a"),
                                    ]),
                            ],
                            selection: $dialogPage, closeTitle: "Close", closeIdentifier: "gallery-dialog-close", onClose: {}
                        ) { page in
                            Form { Text(verbatim: page) }.formStyle(.grouped)
                        }
                        .frame(height: Size.settingsHeight / 2)
                        .listRowInsets(EdgeInsets())
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
                    Section("AIChangeReview") {
                        AIChangeReview(
                            items: [
                                .init(id: "1", kind: .rewrite, title: "He know → He knows", why: "Third person singular.", state: .pending),
                                .init(id: "2", kind: .insert, title: "Add a summary", state: .pending),
                                .init(
                                    id: "3", kind: .rewrite, title: "Tighten the intro", state: .approved,
                                    runs: [.init("Leave on ", .same), .init("Saturday", .added), .init(" morning.", .same)]),
                                .init(
                                    id: "4", kind: .delete, title: "Drop the old note", state: .approved,
                                    runs: [.init("An old note", .removed)]),
                            ],
                            reviewed: [
                                .init(
                                    id: "4", kind: .delete, title: "Drop the old note", state: .approved,
                                    runs: [.init("An old note", .removed)]),
                                .init(
                                    id: "3", kind: .rewrite, title: "Tighten the intro", state: .approved,
                                    runs: [.init("Leave on ", .same), .init("Saturday", .added), .init(" morning.", .same)]),
                            ],
                            activeID: "1", onFocus: { _ in }, onApprove: { _ in }, onSkip: { _ in }, onApproveAll: {})
                    }
                    Section("SkeletonLines") {
                        SkeletonLines([0.45], height: Spacing.s6, label: "app:history.loading")
                        SkeletonLines([1, 0.94, 0.62], label: "app:history.loading")
                    }
                    Section("ThinkingTimeline") {
                        ThinkingTimeline(
                            header: "Checking the dates", isStreaming: true,
                            steps: [.init(id: 0, kind: .thinking, title: "Reading the page", detail: "The trip is in May.")])
                        ThinkingTimeline(
                            header: "Thought for 12 seconds", isStreaming: false,
                            steps: [
                                .init(id: 0, kind: .thinking, title: "Reading the page", detail: "The trip is in May."),
                                .init(id: 1, kind: .search, title: "Searched for “Kyoto weather May”"),
                            ])
                    }
                    Section("ShimmerText") {
                        ShimmerText("app:ai.thinking").font(.hk(.sm))
                        ShimmerText("app:ai.searching").font(.hk(.sm))
                    }
                    Section("CodeBlockView") {
                        CodeBlockView(
                            code: "let greeting = \"Hello\"\nprint(greeting)  // a line long enough to scroll sideways in the block",
                            language: "swift", copyLabel: "app:ai.code.copy", copiedLabel: "app:ai.code.copied")
                    }
                    Section("TextTable") {
                        TextTable(
                            header: ["Model", "Context"], rows: [["Small", "128k"], ["Large", "1M"]],
                            alignments: [.leading, .trailing])
                    }
                    Section("TaskProgressRow") {
                        TaskProgressRow(Text(verbatim: "Importing 3 of 20"), done: 3, total: 20, cancelTitle: "Cancel") {}
                        TaskProgressRow(Text(verbatim: "Reading files…"), done: 0, total: 0, cancelTitle: "Cancel") {}
                    }
                    Section("BarIconButton + SidebarIconButton") {
                        HStack(spacing: Spacing.s2) {
                            BarIconButton("Back", symbol: .caretLeft) {}
                            BarIconButton("Favorite", symbol: .starFill, tint: Theme.primary) {}
                            SidebarIconButton("New page", symbol: .plus) {}
                            SidebarIconButton("More", symbol: .dotsThree) {}
                        }
                    }
                    Section("PageIcon") {
                        HStack(spacing: Spacing.s3) {
                            PageIcon("🌱")
                            PageIcon("📚", size: TextSize.xl.rawValue)
                            PageIcon(nil, size: TextSize.lg.rawValue)
                        }
                    }
                    Section("SelectableCard") {
                        HStack(spacing: Spacing.s2) {
                            SelectableCard("On this device", detail: "Only here", icon: .house, isSelected: true) {}
                            SelectableCard("In a folder", detail: "iCloud Drive", icon: .folderSimple, isSelected: false) {}
                        }
                    }
                    Section("GlassSearchField + SidebarFooterLabel") {
                        GlassSearchField("Search", shortcut: "⌘K") {}
                        SidebarFooterLabel(title: "My notebook") {
                            Circle().fill(Theme.muted).frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                        }
                    }
                    Section("TabStrip") {
                        TabStrip(
                            items: [
                                TabStripItem(id: galleryTabs[0], title: "Welcome to Hikki", icon: "👋"),
                                TabStripItem(id: galleryTabs[1], title: "Home", symbol: .house),
                            ],
                            activeID: galleryTabs[0], canGoBack: true, canGoForward: false,
                            onSelect: { _ in }, onClose: { _ in }, onNew: {}, onBack: {}, onForward: {})
                    }
                    Section("ToastStack") {
                        ToastStack(galleryToasts) { toast in
                            ToastView(kind: .info, message: toast.message, close: {})
                        }
                    }
                    Section("ColorToneSwatch") {
                        HStack(spacing: Spacing.s2) {
                            ForEach(ColorTone.allCases) { ColorToneSwatch($0) }
                        }
                    }
                    Section("HighlightedText") {
                        HighlightedText("The roadmap is due Friday, after the review", terms: ["roadmap", "friday"])
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
