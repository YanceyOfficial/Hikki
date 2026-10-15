#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The iPhone's first screen (the collapsed split view's sidebar column), Notion's: a top bar with ☰ and the title,
    /// All pages and Trash as two tiles, the pages last edited as cards and favorites — no grouped list, no dividers —
    /// over the floating bar (Search · Ask AI · New page). The page tree lives in the side drawer (`PhoneDrawer`), which
    /// ☰ or a swipe from the left slides out (`SideDrawer`). Rows open their page through the navigator, which shows the
    /// detail column (`Navigator.compactColumn`).
    struct PhoneHome: View {
        @Environment(AppModel.self) private var model
        @Bindable var navigator: Navigator
        @State private var isDrawerOpen = false

        var body: some View {
            SideDrawer(isOpen: $isDrawerOpen, closeLabel: "app:drawer.close") {
                PhoneDrawer(navigator: navigator) { setDrawer(open: false) }
            } content: {
                home
            }
            .background(Theme.sidebar)
            .toolbar(.hidden, for: .navigationBar)
            // Something opened from elsewhere (search, a link): the drawer is shut when Home shows again.
            .onChange(of: navigator.compactColumn) { _, column in
                if column == .detail { isDrawerOpen = false }
            }
        }

        private var home: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    places
                    if !recents.isEmpty { recentCards }
                    quickCreate
                    askAI
                    weekCard.padding(.horizontal, Spacing.s4)
                    if !recentlyEdited.isEmpty { recentList }
                    if !model.tree.favorites.isEmpty {
                        section("app:sidebar.favorites") {
                            ForEach(model.tree.favorites) { page in
                                PhonePageRow(page: page, navigator: navigator)
                            }
                        }
                    }
                }
                .padding(.top, Spacing.s2)
                .padding(.bottom, Size.floatingBar + Spacing.s12)
            }
            .scrollIndicators(.hidden)
            .background(Theme.background)
            .safeAreaInset(edge: .top, spacing: Spacing.s0) { topBar }
            .safeAreaInset(edge: .bottom) {
                FloatingActionBar(
                    leading: .init("app:nav.search", icon: .magnifyingGlass, identifier: "sidebar-search") {
                        navigator.isSearching = true
                    },
                    prompt: "app:ai.ask", promptIdentifier: "ask-ai",
                    onPrompt: { navigator.isAskingAI = true },
                    trailing: .init("app:page.new", icon: .notePencil, identifier: "new-page") { navigator.newPage() }
                )
                .padding(.bottom, Spacing.s2)
            }
        }

        private func setDrawer(open: Bool) {
            withAnimation(Motion.easeOut()) { isDrawerOpen = open }
        }

        // MARK: Parts

        /// ☰ (the drawer), the title, and ⋯ (import, settings).
        private var topBar: some View {
            HStack(spacing: Spacing.s2_5) {
                Button {
                    setDrawer(open: !isDrawerOpen)
                } label: {
                    IconView(.list, size: TextSize.xl.rawValue)
                        .foregroundStyle(Theme.foreground)
                        .frame(width: Size.iconButton + Spacing.s3, height: Size.iconButton + Spacing.s3)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(Text("app:drawer.open"))
                .accessibilityIdentifier("drawer-toggle")
                Text("app:nav.home")
                    .font(.hk(.lg, .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.s2)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .background(Theme.background)
        }

        /// All pages and Trash, side by side.
        private var places: some View {
            HStack(spacing: Spacing.s2_5) {
                PlaceTile(title: "app:home.allPages", icon: .house, count: model.tree.all.count, tinted: true) {
                    navigator.go(.home)
                }
                .accessibilityIdentifier("nav-home")
                PlaceTile(title: "app:nav.trash", icon: .trash, count: model.trash.count, tinted: false) {
                    navigator.go(.trash)
                }
                .accessibilityIdentifier("nav-trash")
            }
            .padding(.horizontal, Spacing.s4)
        }

        // MARK: Quick create, Ask AI, recently edited

        /// A page in one tap: blank, today's note (opened again if it exists), or what the clipboard holds.
        private var quickCreate: some View {
            VStack(alignment: .leading, spacing: Spacing.s2_5) {
                SectionTitle("app:home.quickCreate").padding(.horizontal, Spacing.s4)
                HStack(spacing: Spacing.s2_5) {
                    QuickCreateTile(title: "app:home.blankPage", icon: .notePencil) { navigator.newPage() }
                        .accessibilityIdentifier("home-new-blank")
                    QuickCreateTile(title: "app:home.todayNote", icon: .calendarDots) { openTodayNote() }
                        .accessibilityIdentifier("home-new-today")
                    QuickCreateTile(title: "app:home.fromClipboard", icon: .clipboardText) { pasteNote() }
                        .accessibilityIdentifier("home-new-clipboard")
                }
                .padding(.horizontal, Spacing.s4)
            }
        }

        /// Today's note: a top-level page titled with the date — the one made today if there is one.
        private func openTodayNote() {
            let title = Date.now.formatted(date: .long, time: .omitted)
            if let page = model.tree.all.first(where: {
                $0.parentId == nil && $0.title == title && Calendar.current.isDateInToday($0.createdAt)
            }) {
                navigator.open(page.id)
            } else {
                navigator.newPage(QuickNote(title: title, lines: []))
            }
        }

        private func pasteNote() {
            guard let text = UIPasteboard.general.string, let note = QuickNote.fromClipboard(text) else {
                Toasts.shared.show(.info, String(localized: "app:home.clipboardEmpty"))
                return
            }
            navigator.newPage(note)
        }

        /// Questions for Ask AI about what was written lately, sent with those pages as context.
        private var askAI: some View {
            VStack(alignment: .leading, spacing: Spacing.s2_5) {
                SectionTitle("app:home.askAI").padding(.horizontal, Spacing.s4)
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.s2) {
                        suggestion("app:home.ai.summarizeWeek", pages: weekPages)
                        suggestion("app:home.ai.quiz", pages: Array(recents.prefix(5)))
                        suggestion("app:home.ai.today", pages: recents.filter { Calendar.current.isDateInToday($0.updatedAt) })
                    }
                    .padding(.horizontal, Spacing.s4)
                }
                .scrollIndicators(.hidden)
            }
        }

        private func suggestion(_ title: String.LocalizationValue, pages: [PageSummary]) -> some View {
            Button {
                navigator.pendingAIQuestion = (String(localized: title), pages.map(\.id))
                navigator.isAskingAI = true
            } label: {
                HStack(spacing: Spacing.s1_5) {
                    AIGlyph(size: TextSize.sm.rawValue)
                    Text(String(localized: title)).font(.hk(.sm)).foregroundStyle(Theme.foreground).lineLimit(1)
                }
                .padding(.horizontal, Spacing.s3)
                .frame(height: Size.iconButton + Spacing.s3)
                .background(Theme.muted, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-ai-suggestion")
        }

        /// Pages edited in the last 7 days, newest first.
        private var weekPages: [PageSummary] {
            let start = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
            return Array(model.tree.all.filter { $0.updatedAt >= start }.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
        }

        /// This week's edits beyond the cards above, by day.
        private var recentlyEdited: [PageSummary] { Array(weekPages.dropFirst(recents.count).prefix(10)) }

        private var recentList: some View {
            VStack(alignment: .leading, spacing: Spacing.s0) {
                SectionTitle("app:home.recentlyEdited").padding(.horizontal, Spacing.s4).padding(.bottom, Spacing.s1)
                ForEach(RecencyGroup.grouped(recentlyEdited, by: \.updatedAt), id: \.group) { group in
                    ForEach(group.items) { page in
                        PhonePageRow(page: page, navigator: navigator)
                    }
                }
            }
        }

        /// This week's writing (the store's daily activity): words added over the last 7 days, a bar per day, totals.
        private var weekCard: some View {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let activity = model.activity(days: 7)
            let byDay = Dictionary(activity.map { (calendar.startOfDay(for: $0.day), $0.wordsAdded) }, uniquingKeysWith: +)
            let symbols = calendar.veryShortStandaloneWeekdaySymbols
            let days = (0..<7).map { offset -> WeekActivityCard.Day in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                return WeekActivityCard.Day(
                    id: offset, label: symbols[calendar.component(.weekday, from: day) - 1], value: max(0, byDay[day] ?? 0),
                    isToday: offset == 6)
            }
            let stats = model.stats()
            return WeekActivityCard(
                title: "app:home.thisWeek", headline: days.map(\.value).reduce(0, +).formatted(),
                caption: String(localized: "app:home.wordsWritten"), days: days,
                footnote: String(localized: "app:home.totals \(stats.pages.formatted()) \(stats.words.formatted())")
            )
            .accessibilityIdentifier("home-week")
        }

        /// The pages edited last, newest first.
        private var recents: [PageSummary] {
            Array(model.tree.all.sorted { $0.updatedAt > $1.updatedAt }.prefix(8))
        }

        private var recentCards: some View {
            VStack(alignment: .leading, spacing: Spacing.s2_5) {
                SectionTitle("app:home.jumpBackIn").padding(.horizontal, Spacing.s4)
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.s2_5) {
                        ForEach(recents) { page in
                            RecentCard(page: page) { navigator.open(page.id) }
                                .contextMenu { PageActions(page: page, navigator: navigator) }
                        }
                    }
                    .padding(.horizontal, Spacing.s4)
                }
                .scrollIndicators(.hidden)
            }
        }

        private func section(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: Spacing.s0) {
                SectionTitle(title).padding(.horizontal, Spacing.s4).padding(.bottom, Spacing.s1)
                rows()
            }
        }
    }

    /// A small grey section label ("Jump back in", "Pages").
    struct SectionTitle: View {
        let title: LocalizedStringKey
        init(_ title: LocalizedStringKey) { self.title = title }

        var body: some View {
            Text(title)
                .font(.hk(.md, .semibold))
                .foregroundStyle(Theme.mutedForeground)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// All pages / Trash: an icon over the name and a count.
    /// A small tile that makes a page (Home → Quick create).
    private struct QuickCreateTile: View {
        let title: LocalizedStringKey
        let icon: Icon
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    IconView(icon, size: TextSize.lg.rawValue).foregroundStyle(Theme.subtleForeground)
                    Text(title).font(.hk(.sm, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.xl))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private struct PlaceTile: View {
        let title: LocalizedStringKey
        let icon: Icon
        let count: Int
        let tinted: Bool
        let action: () -> Void
        @Environment(\.colorTone) private var tone

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: Spacing.s3_5) {
                    IconView(icon, size: TextSize.x2l.rawValue)
                        .foregroundStyle(tinted ? tone.ink : Theme.subtleForeground)
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.hk(.base, .semibold)).foregroundStyle(Theme.foreground)
                        Spacer(minLength: Spacing.s1)
                        Text(count, format: .number)
                            .font(.hk(.md))
                            .monospacedDigit()
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                .padding(.horizontal, Spacing.s3_5)
                .padding(.vertical, Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.xl + Spacing.s0_5))
                .contentShape(.rect(cornerRadius: Radius.xl + Spacing.s0_5))
            }
            .buttonStyle(PressableStyle())
        }
    }

    /// A page edited lately: a band of colour (picked from the page id, so it stays), its icon, title and when.
    private struct RecentCard: View {
        let page: PageSummary
        let action: () -> Void

        private static let bands: [Color] = [
            Theme.washGreen, Theme.washBlue, Theme.washPurple, Theme.washOrange, Theme.washPink, Theme.washYellow,
            Theme.washBrown,
        ]

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: Spacing.s0) {
                    band.frame(height: Spacing.s10 + Spacing.s1)
                    PageIcon(page.icon, size: TextSize.x2l.rawValue)
                        .padding(.top, -(Spacing.s3_5))
                        .padding(.leading, Spacing.s3)
                    VStack(alignment: .leading, spacing: Spacing.s0_5) {
                        Text(verbatim: page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                            .font(.hk(.sm, .semibold))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Text(page.updatedAt, format: .relative(presentation: .named))
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Spacing.s3)
                    .padding(.top, Spacing.s2)
                    .padding(.bottom, Spacing.s3)
                }
                .frame(width: Size.recentCard, alignment: .leading)
                .background(Theme.muted)
                .clipShape(.rect(cornerRadius: Radius.xl + Spacing.s0_5))
                .contentShape(.rect(cornerRadius: Radius.xl + Spacing.s0_5))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("recent-\(page.title)")
        }

        private var band: Color {
            let sum = page.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            return Self.bands[sum % Self.bands.count]
        }
    }

    private struct PhonePageRow: View {
        let page: PageSummary
        let navigator: Navigator

        var body: some View {
            HStack(spacing: Spacing.s1) {
                Button {
                    navigator.open(page.id)
                } label: {
                    HStack(spacing: Spacing.s2_5) {
                        PageIcon(page.icon, size: TextSize.lg.rawValue)
                            .frame(width: Size.iconButton)
                        Text(verbatim: page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                            .font(.hk(.base))
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: Size.row + Spacing.s3)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("page-row-\(page.title)")
            }
            .padding(.leading, Spacing.s4)
            .padding(.trailing, Spacing.s4)
            .contextMenu { PageActions(page: page, navigator: navigator) }
        }
    }

    /// The 97 % press of the design's buttons, for whole cards and tiles.
    struct PressableStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.easeOut(Motion.popOut), value: configuration.isPressed)
        }
    }
#endif
