import SwiftUI

/// One of the About page's links: the website, the privacy policy, a mail to the developer.
public struct AboutLink: Identifiable {
    public let id: String
    public let title: LocalizedStringKey
    public let icon: Icon
    public let url: URL

    public init(id: String, title: LocalizedStringKey, icon: Icon, url: URL) {
        self.id = id
        self.title = title
        self.icon = icon
        self.url = url
    }
}

/// The top of Settings → About: the app's icon, its name and line, the version (selectable, for a bug report) and
/// its links as a row of outline buttons — none when the app lists them as rows of its own (a phone's Settings).
/// Plain values — the app passes the version and the addresses.
public struct AboutHeader: View {
    let version: String
    /// Where this build came from (TestFlight, a Debug build); nil for the App Store's own, which shows nothing.
    let build: String?
    let links: [AboutLink]

    public init(version: String, build: String? = nil, links: [AboutLink]) {
        self.version = version
        self.build = build
        self.links = links
    }

    public var body: some View {
        VStack(spacing: Spacing.s4) {
            Image("AppMark", bundle: .module)
                .resizable()
                .scaledToFit()
                .frame(width: Size.aboutIcon, height: Size.aboutIcon)
                .clipShape(.rect(cornerRadius: Size.aboutIcon * 0.225, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Size.aboutIcon * 0.225, style: .continuous)
                        .strokeBorder(Theme.border)
                }
                .accessibilityHidden(true)
            VStack(spacing: Spacing.s1) {
                Text(verbatim: "Hikki").font(.hk(.x2l, .semibold)).foregroundStyle(Theme.foreground)
                Text("app:about.tagline").font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                Text("app:about.version \(version)")
                    .font(.hk(.xs).monospacedDigit())
                    .foregroundStyle(Theme.mutedForeground)
                    .textSelection(.enabled)
                    .padding(.top, Spacing.s1)
                    .accessibilityIdentifier("about-version")
                if let build {
                    Text(build)
                        .font(.hk(.xs, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, Spacing.s0_5)
                        .background(Theme.muted, in: .capsule)
                        .accessibilityIdentifier("about-build")
                }
            }
            if !links.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.s2) { linkButtons }
                    VStack(spacing: Spacing.s2) { linkButtons }
                }
                .padding(.top, Spacing.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s4)
    }

    private var linkButtons: some View {
        ForEach(links) { link in
            Link(destination: link.url) {
                // Words and icon, on one line: wrappable words (or the automatic style's icon-only fallback) let
                // the row "fit" by breaking "Websit / e" instead of the links stacking.
                IconLabel(link.title, icon: link.icon).labelStyle(.titleAndIcon).fixedSize()
            }
            .buttonStyle(HikkiButtonStyle(.outline))
            .accessibilityIdentifier("about-link-\(link.id)")
        }
    }
}

#Preview {
    Form {
        Section {
            AboutHeader(
                version: "0.1.0 (1)", build: "TestFlight",
                links: [
                    AboutLink(
                        id: "website", title: "app:about.website", icon: .globe,
                        url: URL(string: "https://hikki.yancey.app")!),
                    AboutLink(
                        id: "privacy", title: "app:about.privacy", icon: .lockSimple,
                        url: URL(string: "https://hikki.yancey.app/privacy")!),
                    AboutLink(
                        id: "contact", title: "app:about.contact", icon: .at,
                        url: URL(string: "mailto:developer@yanceyleo.com")!),
                ])
        }
    }
    .formStyle(.grouped)
}
