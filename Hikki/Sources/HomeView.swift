import Charts
import HikkiCore
import HikkiUI
import SwiftUI

/// Home: a greeting, this workspace at a glance (totals, a writing heatmap, words over the last month) and
/// the pages to jump back into. Native SwiftUI + Swift Charts, painted in the colour tone.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator

    /// Activity loaded for up to a year; the heatmap shows as many weeks as fit its width.
    private static let weeks = 53
    @State private var activity: [DailyActivity] = []
    @State private var stats = WorkspaceStats(pages: 0, words: 0)
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// Four tiles across on a wide window, two by two on an iPhone (four wrapped every label).
    private var statColumns: Int {
        #if os(iOS)
            sizeClass == .compact ? 2 : 4
        #else
            4
        #endif
    }

    var body: some View {
        ScrollView {
            // One container so neighbouring glass shapes blend and render together.
            GlassEffectContainer(spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    header
                    statTiles
                    HomeCard {
                        ActivityHeatmap(activity: activity, weeks: Self.weeks)
                    } title: {
                        Text("app:home.activity")
                    } subtitle: {
                        Text("app:home.activity.summary \(String(activity.reduce(0) { $0 + $1.edits }))")
                    }
                    HomeCard {
                        WritingChart(activity: activity)
                    } title: {
                        Text("app:home.writing")
                    } subtitle: {
                        Text("app:home.writing.subtitle")
                    }
                    recent
                }
            }
            .frame(maxWidth: 920)  // design-lint: allow (reading width)
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s10)
            .frame(maxWidth: .infinity)
        }
        // Glass needs something to refract: a soft wash of the colour tone behind the page.
        .background { HomeBackdrop() }
        .navigationTitle("app:nav.home")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        // Reload when pages change (an edit, a new page); cheap aggregate queries.
        .task(id: model.tree) {
            activity = model.activity(days: Self.weeks * 7)
            stats = model.stats()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(greeting).font(.largeTitle.bold())
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                navigator.newPage()
            } label: {
                IconLabel("app:page.new", icon: .notePencil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("home-new-page")
        }
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "app:home.goodMorning"
        case 12..<18: "app:home.goodAfternoon"
        default: "app:home.goodEvening"
        }
    }

    // MARK: Totals

    private var statTiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s3), count: statColumns), spacing: Spacing.s3) {
            StatTile(value: stats.pages, title: "app:home.stat.pages", icon: .files)
            StatTile(value: stats.words, title: "app:home.stat.words", icon: .textAa)
            StatTile(value: ActivitySummary.editsThisWeek(activity, today: .now), title: "app:home.stat.week", icon: .pencilLine)
            StatTile(value: ActivitySummary.streak(activity, today: .now), title: "app:home.stat.streak", icon: .flame)
        }
    }

    // MARK: Recently edited

    @ViewBuilder private var recent: some View {
        let pages = model.tree.recent(limit: 8)
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("app:home.recentlyEdited").font(.title3.bold())
            if pages.isEmpty {
                Text("app:home.empty").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Spacing.s3)], spacing: Spacing.s3) {
                    ForEach(pages) { page in
                        Button {
                            navigator.open(page.id)
                        } label: {
                            RecentPageCard(page: page, parent: model.tree.path(to: page.id).dropLast().last)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home-recent-\(page.title)")
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// Blurred shapes in the colour tone behind Home, for its glass to pick up.
private struct HomeBackdrop: View {
    @Environment(\.colorTone) private var tone

    var body: some View {
        ZStack {
            Theme.background
            Circle().fill(tone.fill.opacity(0.28)).frame(width: 520, height: 520).blur(radius: 140).offset(x: -260, y: -260)
            Circle().fill(tone.fill.opacity(0.16)).frame(width: 640, height: 640).blur(radius: 160).offset(x: 320, y: 120)
            Ellipse().fill(tone.ink.opacity(0.10)).frame(width: 700, height: 360).blur(radius: 150).offset(x: -80, y: 520)
        }
        .ignoresSafeArea()
    }
}

/// A titled panel on Home.
private struct HomeCard<Content: View, Title: View, Subtitle: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let title: Title
    @ViewBuilder let subtitle: Subtitle

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                title.font(.title3.bold())
                subtitle.font(.subheadline).foregroundStyle(.secondary)
            }
            content
        }
        .padding(Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.xl))
    }
}

/// One number with its label, the icon in the colour tone.
private struct StatTile: View {
    let value: Int
    let title: LocalizedStringKey
    let icon: Icon
    @Environment(\.colorTone) private var tone

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            IconView(icon, size: TextSize.lg.rawValue).foregroundStyle(tone.fill)
            Text(value, format: .number)
                .font(.title.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.xl))
    }
}

/// GitHub-style grid: a column per week, a cell per day, deeper tone for busier days.
private struct ActivityHeatmap: View {
    let activity: [DailyActivity]
    let weeks: Int
    @Environment(\.colorTone) private var tone

    @State private var width: CGFloat = 0

    var body: some View {
        let byDay = Dictionary(activity.map { (ActivityDay.key($0.day), $0.edits) }, uniquingKeysWith: +)
        let busiest = byDay.values.max() ?? 0
        // As many weeks as fit the card's width (up to `weeks`), ending with this one.
        let step = Size.heatmapCell + Spacing.s1
        let fitting = max(1, min(weeks, Int((width + Spacing.s1) / step)))
        let grid = ActivitySummary.grid(weeks: fitting, today: .now)
        VStack(alignment: .leading, spacing: Spacing.s2) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                monthLabels(grid)
                HStack(alignment: .top, spacing: Spacing.s1) {
                    ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: Spacing.s1) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                cell(day, edits: day.map { byDay[ActivityDay.key($0)] ?? 0 } ?? 0, busiest: busiest)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            legend
        }
    }

    @ViewBuilder private func cell(_ day: Date?, edits: Int, busiest: Int) -> some View {
        if let day {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(color(level: ActivitySummary.level(edits, max: busiest)))
                .frame(width: Size.heatmapCell, height: Size.heatmapCell)
                .help(String(localized: "app:home.activity.day \(String(edits)) \(day.formatted(.dateTime.month().day()))"))
        } else {
            Color.clear.frame(width: Size.heatmapCell, height: Size.heatmapCell)
        }
    }

    private func color(level: Int) -> AnyShapeStyle {
        level == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(tone.fill.opacity([0, 0.3, 0.5, 0.75, 1][level]))
    }

    /// A month's short name above the first week that starts in it.
    private func monthLabels(_ grid: [[Date?]]) -> some View {
        HStack(spacing: Spacing.s1) {
            ForEach(Array(grid.enumerated()), id: \.offset) { index, week in
                Text(isNewMonth(grid, index) ? (week.compactMap { $0 }.first?.formatted(.dateTime.month(.abbreviated)) ?? "") : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: Size.heatmapCell, alignment: .leading)
            }
        }
    }

    private func isNewMonth(_ grid: [[Date?]], _ index: Int) -> Bool {
        guard let first = grid[index].compactMap({ $0 }).first else { return false }
        guard index > 0, let previous = grid[index - 1].compactMap({ $0 }).first else { return true }
        return !Calendar.current.isDate(first, equalTo: previous, toGranularity: .month)
    }

    private var legend: some View {
        HStack(spacing: Spacing.s1) {
            Spacer()
            Text("app:home.less").font(.caption).foregroundStyle(.secondary)
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(color(level: level))
                    .frame(width: Size.heatmapCell, height: Size.heatmapCell)
            }
            Text("app:home.more").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Words added per day over the last 30 days.
private struct WritingChart: View {
    let activity: [DailyActivity]
    @Environment(\.colorTone) private var tone

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today
        let end = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        Chart(activity.filter { $0.day >= start }, id: \.day) { day in
            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Words", day.wordsAdded))
                .foregroundStyle(tone.fill.gradient)
                .clipShape(.rect(cornerRadius: Radius.sm))
        }
        .chartXScale(domain: start...end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 160)  // design-lint: allow (chart height)
    }
}

/// A page to jump back into: its icon on a tinted tile, title, where it lives and when it was edited.
private struct RecentPageCard: View {
    let page: PageSummary
    let parent: PageSummary?
    @Environment(\.colorTone) private var tone

    var body: some View {
        HStack(spacing: Spacing.s3) {
            PageIcon(page.icon, size: TextSize.x2l.rawValue)
                .frame(width: Size.iconButton + Spacing.s4, height: Size.iconButton + Spacing.s4)
                .background(tone.selectionFill, in: .rect(cornerRadius: Radius.lg))
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                Text(page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                    .font(.headline)
                    .foregroundStyle(page.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if let parent {
                    Text("app:home.in \(parent.title.isEmpty ? String(localized: "app:page.untitled") : parent.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(page.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: Radius.xl))
        // Interactive glass: it reacts to hover and press itself.
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.xl))
    }
}
