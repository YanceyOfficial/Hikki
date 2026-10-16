#if os(iOS)
    import HikkiCore
    import HikkiUI
    import SwiftUI

    /// The page's ⋯ on iPhone: a sheet instead of a long menu — the page on top, four quick actions as tiles, the rest
    /// as rows, and the page's facts at the end (what the Mac's inspector Info and ⋯ menu hold).
    struct PhonePageActions: View {
        @Environment(AppModel.self) private var model
        @Environment(\.dismiss) private var dismiss
        let page: PageSummary
        let navigator: Navigator
        let editor: EditorController

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    header
                    quickActions
                    rows
                    facts
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s5)
                .padding(.bottom, Spacing.s6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }

        private var path: [String] {
            model.tree.path(to: page.id).dropLast().map(Self.name)
        }

        private var header: some View {
            HStack(spacing: Spacing.s3) {
                PageIcon(page.icon, size: TextSize.x2l.rawValue)
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text(verbatim: Self.name(page)).font(.hk(.lg, .semibold)).lineLimit(1)
                    if !path.isEmpty {
                        Text(verbatim: path.joined(separator: " › "))
                            .font(.hk(.md))
                            .foregroundStyle(Theme.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Spacing.s2)
            }
        }

        private var quickActions: some View {
            HStack(spacing: Spacing.s2) {
                QuickTile(title: "app:page.copyLink", icon: .link) {
                    PageLink.copyToPasteboard(page.id)
                    dismiss()
                }
                QuickTile(title: "app:find.short", icon: .magnifyingGlass) {
                    dismiss()
                    editor.find(.find)
                }
                .accessibilityIdentifier("find-in-page")
                QuickTile(title: page.isLocked ? "app:page.unlock" : "app:page.lock", icon: page.isLocked ? .lockSimpleOpen : .lockSimple) {
                    model.setLocked(!page.isLocked, id: page.id)
                }
                .accessibilityIdentifier("lock-toggle")
                QuickTile(title: "app:page.addSubpage", icon: .plus) {
                    dismiss()
                    navigator.newPage(parentId: page.id)
                }
            }
        }

        private var rows: some View {
            VStack(spacing: Spacing.s0) {
                if !page.isLocked {
                    ActionRow(title: "app:page.cover", icon: .image) {
                        dismiss()
                        // After this sheet has gone, so the editor's own sheet isn't covered by it.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editor.editCover() }
                    }
                    .accessibilityIdentifier("page-cover")
                }
                ActionRow(title: "app:history.open", icon: .clockCounterClockwise) {
                    dismiss()
                    navigator.historyPageID = page.id
                }
                .accessibilityIdentifier("page-history")
                Menu {
                    ForEach(PageExport.Format.allCases) { format in
                        Button(format.title) {
                            dismiss()
                            navigator.exportRequest = ExportRequest(pageID: page.id, format: format)
                        }
                        .accessibilityIdentifier("export-\(format.rawValue)")
                    }
                } label: {
                    ActionRowLabel(title: "app:export.menu", icon: .export, chevron: true)
                }
                .accessibilityIdentifier("page-export")
                Menu {
                    if page.parentId != nil {
                        Button("app:page.moveToTopLevel") { model.movePageToTopLevel(page.id) }
                    }
                    ForEach(model.tree.moveTargets(for: page.id), id: \.page.id) { target in
                        Button {
                            model.movePage(page.id, onto: target.page.id, zone: .inside)
                        } label: {
                            Text(verbatim: String(repeating: "    ", count: target.depth) + Self.title(target.page))
                        }
                    }
                } label: {
                    ActionRowLabel(title: "app:page.moveTo", icon: .arrowBendUpRight, chevron: true)
                }
                ActionRow(title: "app:page.duplicate", icon: .copy) {
                    model.duplicate(id: page.id)
                    dismiss()
                }
                ActionRow(title: "app:page.moveToTrash", icon: .trash, destructive: true) {
                    dismiss()
                    model.moveToTrash(id: page.id)
                }
            }
            .background(Theme.muted, in: .rect(cornerRadius: Radius.xl + Spacing.s1))
        }

        private var facts: some View {
            let info = editor.pageInfo.flatMap { $0.docId == page.id ? $0 : nil }
            return Grid(alignment: .leading, horizontalSpacing: Spacing.s4, verticalSpacing: Spacing.s2_5) {
                GridRow {
                    if let info {
                        Fact(label: "app:page.words") { Text(info.words, format: .number) }
                        Fact(label: "app:page.characters") { Text(info.characters, format: .number) }
                    }
                }
                GridRow {
                    Fact(label: "app:page.createdLabel") { Text(page.createdAt, format: .dateTime.year().month().day()) }
                    Fact(label: "app:page.editedLabel") { Text(page.updatedAt, format: .relative(presentation: .named)) }
                }
            }
            .padding(.horizontal, Spacing.s1)
        }

        /// The page's title (or "Untitled").
        static func name(_ page: PageSummary) -> String {
            page.title.isEmpty ? String(localized: "app:page.untitled") : page.title
        }

        /// Icon and title, for the Move to menu.
        static func title(_ page: PageSummary) -> String {
            (page.icon.map { "\($0) " } ?? "") + name(page)
        }
    }

    private struct QuickTile: View {
        let title: LocalizedStringKey
        let icon: Icon
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: Spacing.s1_5) {
                    IconView(icon, size: TextSize.x2l.rawValue)
                    Text(title).font(.hk(.xs)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s3)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.xl + Spacing.s1))
                .contentShape(.rect(cornerRadius: Radius.xl + Spacing.s1))
            }
            .buttonStyle(PressableStyle())
        }
    }

    private struct ActionRow: View {
        let title: LocalizedStringKey
        let icon: Icon
        var destructive = false
        let action: () -> Void

        var body: some View {
            Button(action: action) { ActionRowLabel(title: title, icon: icon, destructive: destructive) }
                .buttonStyle(.plain)
        }
    }

    private struct ActionRowLabel: View {
        let title: LocalizedStringKey
        let icon: Icon
        var destructive = false
        var chevron = false

        var body: some View {
            HStack(spacing: Spacing.s3_5) {
                IconView(icon, size: TextSize.lg.rawValue).opacity(0.8)
                Text(title).font(.hk(.base))
                Spacer(minLength: Spacing.s2)
                if chevron {
                    IconView(.caretUpDown, size: TextSize.xs.rawValue).foregroundStyle(Theme.placeholder)
                }
            }
            .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(Theme.foreground))
            .padding(.horizontal, Spacing.s4)
            .frame(height: Size.row + Spacing.s4)
            .contentShape(.rect)
        }
    }

    private struct Fact<Value: View>: View {
        let label: LocalizedStringKey
        @ViewBuilder let value: Value

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                Text(label).foregroundStyle(Theme.mutedForeground)
                value.monospacedDigit()
            }
            .font(.hk(.md))
        }
    }
#endif
