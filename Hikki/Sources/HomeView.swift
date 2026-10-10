import HikkiCore
import HikkiUI
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s7) {
                Text(greeting)
                    .font(.hk(.x3l, .bold))
                    .foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Spacing.s12)

                VStack(alignment: .leading, spacing: Spacing.s2_5) {
                    IconLabel("app:home.recentlyEdited", icon: .clock)
                        .font(.hk(.xs, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s3) {
                            ForEach(model.tree.recent(limit: 12)) { page in
                                Button {
                                    navigator.open(page.id)
                                } label: {
                                    PageCard(
                                        title: page.title, icon: page.icon,
                                        subtitle: page.updatedAt.formatted(.relative(presentation: .named)))
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                navigator.newPage()
                            } label: {
                                VStack(spacing: Spacing.s2) {
                                    IconView(.plus, size: TextSize.lg.rawValue)
                                    Text("app:page.new").font(.hk(.md, .medium))
                                }
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(width: 148, height: 132)
                                .background(Theme.accent, in: .rect(cornerRadius: Radius.xl))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home-new-page")
                        }
                        .padding(.vertical, Spacing.s0_5)
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, Spacing.s6)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("app:nav.home")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "app:home.goodMorning"
        case 12..<18: "app:home.goodAfternoon"
        default: "app:home.goodEvening"
        }
    }
}
