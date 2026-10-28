#if DEBUG
    import HikkiCore
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
        @State private var moveQuery = ""
        @State private var moveExpanded: Set<String> = ["work"]
        @State private var findTerm = "apple"
        @State private var findReplaceTerm = ""
        @State private var findOptions = FindBarOptions()
        private let galleryTabs = [UUID(), UUID()]
        private let galleryToasts = [GalleryToast(message: "Page duplicated"), GalleryToast(message: "Link copied")]

        private struct GalleryToast: Identifiable {
            let id = UUID()
            let message: String
        }

        /// MovePagePicker's sample: a small tree, or one search result once something is typed.
        private var galleryMoveItems: [MovePickerItem] {
            guard moveQuery.isEmpty else {
                return [MovePickerItem(id: "sync", title: "Weekly sync", icon: "🗓️", path: "Work / Meetings")]
            }
            let open = moveExpanded.contains("work")
            var items = [MovePickerItem(id: "work", title: "Work", icon: "💼", hasChildren: true, isExpanded: open)]
            if open { items.append(MovePickerItem(id: "roadmap", title: "Roadmap", icon: nil, depth: 1, isCurrent: true)) }
            items.append(MovePickerItem(id: "trip", title: "Trip to Kyoto", icon: "🗾"))
            return items
        }

        /// MonthCalendar's sample: October 2026, a few pages on some days.
        private var galleryWeeks: [[MonthCalendar.Day]] {
            let calendar = HomeCalendar.calendar()
            let month = CalendarMonth(year: 2026, month: 10)
            let pages = [
                MonthCalendar.Page(id: "a", title: "Trip to Kyoto", icon: "🗺️"),
                MonthCalendar.Page(id: "b", title: "Reading notes", icon: nil),
            ]
            return HomeCalendar.weeks(of: month, calendar: calendar).map { week in
                week.map { day in
                    let number = calendar.component(.day, from: day)
                    let count = [0, 1, 0, 2, 4][number % 5]
                    return MonthCalendar.Day(
                        id: day, number: number, inMonth: month.contains(day, in: calendar), isToday: number == 24,
                        pages: Array(pages.prefix(count)), total: count, label: day.formatted(date: .complete, time: .omitted))
                }
            }
        }

        var body: some View {
            NavigationStack {
                ScrollViewReader { proxy in
                    List {
                        Section("ToolbarIconButton") {
                            HStack {
                                ForEach(EditorCommand.allCases.prefix(6)) { command in
                                    ToolbarIconButton(
                                        LocalizedStringKey(command.title), symbol: command.icon,
                                        isActive: active.contains(command.rawValue), style: .quiet
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
                        Section("KeyboardAIComposer") {
                            KeyboardAIComposer(
                                quote: "Hello world", presets: [.init(id: "improve", label: "Improve writing")], onSend: { _ in },
                                onPreset: { _ in }, onClose: {}
                            )
                            .listRowInsets(EdgeInsets())
                        }
                        Section("KeyboardLinkComposer") {
                            KeyboardLinkComposer(quote: "Hikki", href: nil, onApply: { _ in }, onRemove: {}, onClose: {})
                                .listRowInsets(EdgeInsets())
                        }
                        Section("KeyboardCommentComposer") {
                            KeyboardCommentComposer(quote: "Line number 3", onSend: { _ in }, onClose: {})
                                .listRowInsets(EdgeInsets())
                        }
                        Section("BlockActionsSheet") {
                            BlockActionsSheet(
                                info: .init(
                                    kind: "Text", turnInto: "paragraph",
                                    turnIntoItems: [.init(id: "paragraph", label: "Text", icon: .textT)],
                                    textColor: nil, backgroundColor: nil, colorable: true, copyLink: true, comment: true, askAI: true,
                                    words: 2, characters: 11, moveTargets: [.init(id: "a", title: "Trip to Kyoto", icon: "🗾")]),
                                onAction: { _ in }, onTurnInto: { _ in }, onColor: { _, _ in }
                            )
                            .frame(height: 480)
                            .listRowInsets(EdgeInsets())
                        }
                        Section("CommentThreadSheet") {
                            CommentThreadSheet(
                                quote: "Peak is mid-November",
                                comments: [
                                    CommentThreadComment(
                                        id: "1", author: nil, createdAt: .now.addingTimeInterval(-3600), text: "Is this still right?"),
                                    CommentThreadComment(
                                        id: "2", author: "Yancey", device: "Mac", createdAt: .now.addingTimeInterval(-600),
                                        edited: true, text: "Yes — checked @Kyoto trip"),
                                ], onAction: { _ in }, onClose: {}
                            )
                            .frame(height: 420)
                            .listRowInsets(EdgeInsets())
                        }
                        Section("CoverSheet") {
                            CoverSheet(
                                current: "gradient:ocean", startsInPicker: true,
                                search: { _ in .failed(busy: true) },
                                onSelect: { _ in }, onPickPhoto: { _ in }, onUpload: { _ in }, onRemove: {}
                            )
                            .frame(height: 420)
                            .listRowInsets(EdgeInsets())
                        }
                        Section("IconPickerSheet") {
                            IconPickerSheet(
                                title: "app:icon.title",
                                sections: [
                                    IconPickerSection(
                                        id: "smileys", title: "Smileys & emotion",
                                        emojis: ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🙂"].map {
                                            IconPickerEmoji(emoji: $0, label: $0)
                                        })
                                ],
                                recents: [IconPickerEmoji(emoji: "💡", label: "💡")], current: "💡", search: { _ in [] },
                                onPick: { _ in }, onRandom: {}, color: (selected: "blue", onPick: { _ in })
                            )
                            .frame(height: 420)
                            .listRowInsets(EdgeInsets())
                        }
                        Section("FindBar") {
                            FindBar(
                                term: $findTerm, replaceTerm: $findReplaceTerm, options: $findOptions,
                                status: FindBarStatus(count: 3, current: 0), canReplace: true, onStep: { _ in }, onReplace: { _ in },
                                onClose: {}
                            )
                            .listRowInsets(EdgeInsets())
                        }
                        Section("MathComposer") {
                            MathComposer(
                                latex: "\\frac{a}{b}", kind: .inline, onChange: { _ in }, onDone: { _ in }, onCancel: {}, onRemove: {}
                            )
                            .listRowInsets(EdgeInsets())
                        }
                        Section("PublishSheet") {
                            PublishSheet(
                                title: "Trip to Kyoto",
                                tags: ["study", "language", "travel", "food"].map { .init(id: $0, title: $0.capitalized) },
                                maxTags: 3, isPublishing: false, listed: .constant(true), chosenTags: .constant(["travel"]),
                                author: .constant("Yancey"), checked: .constant(false), onPublish: {}, onCancel: {}
                            )
                            .listRowInsets(EdgeInsets())
                        }
                        Section("PublishedSheet") {
                            PublishedSheet(
                                link: "https://hikki.yancey.app/shared/2164cc13", listed: true, tags: ["Travel"], author: "Yancey",
                                onCopy: {}, onOpen: {}, onDone: {}
                            )
                            .listRowInsets(EdgeInsets())
                        }
                        Section("FlowRow") {
                            FlowRow {
                                ForEach(["Study", "Languages", "Work", "Tech", "Design", "Writing"], id: \.self) {
                                    FilterChip(LocalizedStringKey($0), isSelected: $0 == "Tech", look: .filled) {}
                                }
                            }
                        }
                        Section("FileDropZone") {
                            FileDropZone(
                                title: "Drop files or folders here", detail: "Markdown, HTML, text, Hikki JSON, or a Notion export (.zip)",
                                icon: .trayArrowDown, isTargeted: false
                            ) {}
                        }
                        Section("MediaSourceSheet") {
                            MediaSourceSheet { _ in }
                                .listRowInsets(EdgeInsets())
                        }
                        Section("DateSheet") {
                            DateSheet(
                                value: DateSheetValue(day: .now, time: .now, remind: 60), dayTime: "09:00", onChange: { _ in },
                                onDone: {}, onRemove: {}
                            )
                            .frame(height: 640)
                            .listRowInsets(EdgeInsets())
                        }
                        Section("UpcomingList") {
                            UpcomingList(
                                rows: [
                                    .init(id: "1", text: "Send the invoice", when: "Yesterday 5:00 PM", page: "Work", kind: .overdue),
                                    .init(id: "2", text: "Book the ryokan", when: "Tomorrow", page: "Trip to Kyoto", kind: .reminder),
                                    .init(id: "3", text: "Dentist", when: "Friday 9:30 AM", page: "Errands", kind: .date),
                                    .init(id: "4", text: "Renew passport", when: "Oct 30", page: "Errands", kind: .done),
                                ], limit: 3
                            ) { _ in }
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
                                    .init(
                                        id: $0, label: "MTWTFSS".map(String.init)[$0], value: [1, 0, 8, 3, 0, 12, 0][$0], isToday: $0 == 5)
                                },
                                footnote: "32 pages · 41,203 words in all")
                        }
                        Section("MonthCalendar · CalendarDayList") {
                            MonthCalendar(
                                title: "October 2026", summary: "23 pages edited",
                                weekdays: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], weeks: galleryWeeks,
                                selection: galleryWeeks[3][5].id, onSelect: { _ in }, onMove: { _ in }, onToday: {})
                            CalendarDayList(
                                title: "Saturday, October 24",
                                rows: [
                                    .init(
                                        id: "a", title: "Trip to Kyoto", icon: "🗺️", location: "Travel", words: "1,204 words",
                                        time: "3:41 PM"),
                                    .init(id: "b", title: "Reading notes", icon: nil, location: "", words: "312 words", time: "9:02 AM"),
                                ], onOpen: { _ in })
                        }
                        .id("MonthCalendar")
                        Section("PageCoverView") {
                            HStack(spacing: Spacing.s3) {
                                PageCoverView(.gradient(.ocean)).frame(height: Size.homeCardCover)
                                PageCoverView(.gradient(.ember)).frame(height: Size.homeCardCover)
                            }
                        }
                        Section("AboutHeader") {
                            AboutHeader(
                                version: "0.1.0 (1)",
                                links: [
                                    AboutLink(
                                        id: "website", title: "app:about.website", icon: .globe,
                                        url: URL(string: "https://hikki.yancey.app")!),
                                    AboutLink(
                                        id: "contact", title: "app:about.contact", icon: .at,
                                        url: URL(string: "mailto:developer@yanceyleo.com")!),
                                ])
                        }
                        Section("UnlockSheet · ReadOnlyBar") {
                            UnlockSheet(status: .trial(daysLeft: 9), price: "$19.99", onUnlock: {}, onRestore: {}, onClose: {})
                            UnlockSheet(status: .expired, price: "$19.99", onUnlock: {}, onRestore: {}, onClose: {})
                            ReadOnlyBar {}
                        }
                        Section("ToastView") {
                            ToastView(kind: .success, message: "Link copied", close: {})
                            ToastView(kind: .progress, message: "Saving the shared page…", close: {})
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
                                .init(id: 4, style: .table, runs: [.init("文型 | 示例", .same)]),
                                .init(id: 5, style: .table, runs: [.init("～は～です。 | 僕は日本人です。", .same)]),
                                .init(id: 6, style: .table, change: .added, runs: [.init("～も～です。 | ミラーさんも会社員です。", .added)]),
                            ])
                        }
                        .id("VersionDiffView")
                        Section("AIChangeReview") {
                            AIChangeReview(
                                items: [
                                    .init(
                                        id: "1", kind: .rewrite, title: "He know → He knows", why: "Third person singular.", state: .pending
                                    ),
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
                        Section("ImageResultStrip") {
                            ImageResultStrip(
                                items: [
                                    ImageResultItem(
                                        id: "1",
                                        thumbnail: URL(string: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=200")!,
                                        caption: "Kiyomizu-dera", source: URL(string: "https://example.com/kyoto")),
                                    ImageResultItem(id: "2", thumbnail: URL(string: "https://invalid.example/missing.jpg")!),
                                ], onAdd: { _ in }, onOpen: { _ in }, onCopy: { _ in }, load: { try await WebImage.fetch($0).data })
                        }
                        Section("PictureTiles") {
                            PictureTiles(
                                items: [
                                    PictureTileItem(id: "1", state: .done, aspect: 1.5, description: "Torii gates", added: true),
                                    PictureTileItem(id: "2", state: .forming, aspect: 1.5, description: "Bamboo grove"),
                                    PictureTileItem(id: "3", state: .waiting, aspect: 1.5, description: "Pagoda"),
                                    PictureTileItem(id: "4", state: .failed("Stopped"), aspect: 1.5, description: "Night"),
                                ], onAdd: { _ in }, onCover: { _ in }, onRetry: { _ in }, onAddAll: {})
                        }
                        Section("ToolCallCards") {
                            ToolCallCards(
                                items: [
                                    ToolCallCardItem(
                                        id: "1", kind: .find, path: "", pattern: "*.md", state: .done, summary: "2 files",
                                        lines: ["notes/plan.md", "notes/trips/japan.md"]),
                                    ToolCallCardItem(
                                        id: "2", kind: .read, path: "notes/plan.md", state: .done, summary: "3 lines",
                                        lines: ["# Plan", "Book the ryokan.", "Book the train."]),
                                    ToolCallCardItem(
                                        id: "3", kind: .edit, path: "notes/plan.md", state: .waiting,
                                        diff: [
                                            .init(.context, "# Plan"), .init(.removed, "Book the ryokan."),
                                            .init(.added, "Book the hotel."),
                                        ],
                                        added: 1, removed: 1),
                                    ToolCallCardItem(
                                        id: "4", kind: .write, path: "pages/p1.json", state: .failed("pages is Hikki's own data.")),
                                ], onAllow: { _ in }, onDecline: { _ in })
                        }
                        .id("ToolCallCards")
                        Section("ShimmerText") {
                            ShimmerText("app:ai.thinking").font(.hk(.sm))
                            ShimmerText("app:ai.searching").font(.hk(.sm))
                        }
                        Section("SyncStatusBadge") {
                            let saving = String(localized: "app:saveStatus.saving")
                            let synced = String(localized: "app:saveStatus.synced")
                            SyncStatusBadge(kind: .saving, title: saving, detail: saving)
                            SyncStatusBadge(
                                kind: .uploading, title: String(localized: "app:saveStatus.uploading"),
                                detail: String(localized: "app:saveStatus.uploadingDetail"))
                            SyncStatusBadge(kind: .synced, title: synced, detail: synced)
                            SyncStatusBadge(kind: .synced, title: synced, detail: synced, compact: true)
                            SyncStatusBadge(
                                kind: .waiting, title: String(localized: "app:saveStatus.waiting"),
                                detail: String(localized: "app:saveStatus.waitingDetail"))
                            SyncStatusBadge(
                                kind: .trouble, title: String(localized: "app:saveStatus.notSyncing"),
                                detail: String(localized: "app:cloud.noAccount"))
                        }
                        .id("SyncStatusBadge")
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
                        Section("PageRowLabel") {
                            VStack(spacing: Spacing.s0) {
                                PageRowLabel(icon: "🗺️", title: "Trip to Kyoto")
                                PageRowLabel(icon: nil, title: "")
                                PageRowLabel(icon: "📚", title: "Reading notes", nested: true)
                            }
                        }
                        Section("PressEffect · PressableButtonStyle · HikkiButtonStyle") {
                            HStack(spacing: Spacing.s3) {
                                Button {
                                } label: {
                                    Text(verbatim: "A tile")
                                        .padding(Spacing.s4)
                                        .background(Theme.muted, in: .rect(cornerRadius: Radius.lg))
                                }
                                .buttonStyle(.pressable)
                                Button("Continue") {}.buttonStyle(.hikki())
                                Button("Skip") {}.buttonStyle(.hikki(.ghost))
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
                        Section("MovePagePicker") {
                            MovePagePicker(
                                query: $moveQuery, items: galleryMoveItems, workspaceName: "Yancey's Notes", isAtTopLevel: false,
                                focusesField: false,
                                badge: { WorkspaceBadge(initial: "Y") },
                                onToggle: { id in
                                    if moveExpanded.contains(id) { moveExpanded.remove(id) } else { moveExpanded.insert(id) }
                                },
                                onPick: { _ in }, onCancel: {}
                            )
                            .frame(height: Size.movePickerHeight)
                        }
                        Section("SearchMatchRow · SearchMatchesToggleRow") {
                            SearchMatchRow(snippet: "雨が降っているので家にいます。", terms: ["ので"], isSelected: true)
                            SearchMatchRow(snippet: "日本語がわからないので、英語で話していただけませんか。", terms: ["ので"])
                            SearchMatchesToggleRow("12 more matches")
                            SearchMatchesToggleRow("Show fewer", isExpanded: true)
                        }
                    }
                    // HIKKI_GALLERY_SECTION=<section> opens the gallery there (screenshots of one component).
                    .task {
                        if let section = ProcessInfo.processInfo.environment["HIKKI_GALLERY_SECTION"] {
                            proxy.scrollTo(section, anchor: .top)
                        }
                    }
                }
                .navigationTitle("HikkiUI Gallery")
            }
        }
    }
#endif
