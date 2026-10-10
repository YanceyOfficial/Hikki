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
                    Label("Recently edited", systemImage: "clock")
                        .font(.hk(.sm, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s3) {
                            ForEach(model.tree.recent(limit: 12)) { page in
                                Button { navigator.open(page.id) } label: {
                                    PageCard(title: page.title, icon: page.icon,
                                             subtitle: page.updatedAt.formatted(.relative(presentation: .named)))
                                }
                                .buttonStyle(.plain)
                            }
                            Button { navigator.newPage() } label: {
                                VStack(spacing: Spacing.s2) {
                                    Image(systemName: "plus").font(.hk(.xl))
                                    Text("New page").font(.hk(.md, .medium))
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
        .navigationTitle("Home")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
