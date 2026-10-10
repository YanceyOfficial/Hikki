import HikkiCore
import HikkiUI
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(greeting)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 48)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Recently edited", systemImage: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.mutedText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(model.tree.recent(limit: 12)) { page in
                                Button { navigator.open(page.id) } label: {
                                    PageCard(title: page.title, icon: page.icon,
                                             subtitle: page.updatedAt.formatted(.relative(presentation: .named)))
                                }
                                .buttonStyle(.plain)
                            }
                            Button { navigator.newPage() } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "plus").font(.system(size: 18))
                                    Text("New page").font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(Theme.mutedText)
                                .frame(width: 148, height: 132)
                                .background(Theme.hover, in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home-new-page")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
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
