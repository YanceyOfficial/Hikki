import HikkiCore
import HikkiUI
import SwiftUI

/// Device-level appearance choice (Settings → Preferences → Theme), applied at the root of each window.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "app:settings.theme.system"
        case .light: "app:settings.theme.light"
        case .dark: "app:settings.theme.dark"
        }
    }
}

/// Notion-style settings: a section list on the left and the chosen pane on the right (Mac/iPad); a
/// navigation list on iPhone.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case preferences, general, about
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .preferences: "app:settings.preferences"
            case .general: "app:settings.general"
            case .about: "app:settings.about"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .preferences: "app:settings.preferences.subtitle"
            case .general: "app:settings.general.subtitle"
            case .about: "app:settings.about.subtitle"
            }
        }

        var icon: Icon {
            switch self {
            case .preferences: .slidersHorizontal
            case .general: .buildings
            case .about: .info
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var pane: Pane = .preferences

    var body: some View {
        // By device, not size class: an iPad sheet reports a compact width but has room for two columns.
        #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone { compact } else { regular }
        #else
            regular
        #endif
    }

    // MARK: Mac / iPad

    private var regular: some View {
        HStack(spacing: Spacing.s0) {
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                group("app:settings.group.app", panes: [.preferences])
                group("app:settings.group.workspace", panes: [.general])
                group("app:settings.group.hikki", panes: [.about])
                Spacer()
            }
            .padding(.vertical, Spacing.s4)
            .frame(width: Size.sidebarMin)
            .background(Theme.sidebar)
            .overlay(alignment: .trailing) { Theme.sidebarBorder.frame(width: 1) }

            ScrollView {
                PaneView(pane: pane)
                    .padding(.horizontal, Spacing.s12)
                    .padding(.vertical, Spacing.s10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .overlay(alignment: .topTrailing) {
                Button {
                    dismiss()
                } label: {
                    IconView(.x, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                        .frame(width: Size.iconButton, height: Size.iconButton)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text("app:settings.close"))
                .accessibilityIdentifier("settings-close")
                .padding(Spacing.s3)
            }
        }
        #if os(macOS)
            .frame(minWidth: 820, idealWidth: 920, minHeight: 560, idealHeight: 640)  // design-lint: allow (window size)
        #endif
    }

    private func group(_ title: LocalizedStringKey, panes: [Pane]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s0_5) {
            Text(title)
                .font(.hk(.xs, .medium))
                .foregroundStyle(Theme.mutedForeground)
                .padding(.horizontal, Spacing.s3_5)
                .padding(.top, Spacing.s3)
                .padding(.bottom, Spacing.s1)
            ForEach(panes) { item in
                SettingsNavItem(item.title, icon: item.icon, isSelected: pane == item) { pane = item }
                    .accessibilityIdentifier("settings-pane-\(item.rawValue)")
            }
        }
    }

    // MARK: iPhone

    #if os(iOS)
        private var compact: some View {
            NavigationStack {
                List(Pane.allCases) { item in
                    NavigationLink {
                        ScrollView { PaneView(pane: item).padding(Spacing.s5) }
                            .background(Theme.background)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        IconLabel(item.title, icon: item.icon)
                    }
                    .accessibilityIdentifier("settings-pane-\(item.rawValue)")
                }
                .navigationTitle(Text("app:settings.title"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("app:settings.close") { dismiss() }
                            .accessibilityIdentifier("settings-close")
                    }
                }
            }
        }
    #endif
}

/// One settings pane: title, subtitle and its sections.
private struct PaneView: View {
    let pane: SettingsView.Pane

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(pane.title).font(.hk(.x3l, .bold)).foregroundStyle(Theme.foreground)
                Text(pane.subtitle).font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
            }
            switch pane {
            case .preferences: PreferencesPane()
            case .general: GeneralPane()
            case .about: AboutPane()
            }
        }
    }
}

private struct PreferencesPane: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            SettingsSection("app:settings.appearance") {
                SettingsRow("app:settings.theme", detail: "app:settings.theme.detail") {
                    Picker("app:settings.theme", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-theme")
                }
            }
            SettingsSection("app:settings.languageSection") {
                SettingsRow("app:settings.language", detail: "app:settings.language.detail") {
                    Button("app:settings.language.open", action: openLanguageSettings)
                        .buttonStyle(.hikki(.outline))
                }
            }
        }
    }

    /// In-app language switching would need a relaunch; the system's per-app language setting is the
    /// supported place for it.
    private func openLanguageSettings() {
        #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #else
            if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        #endif
    }
}

private struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        SettingsSection("app:settings.group.workspace") {
            SettingsRow("app:settings.name", detail: "app:settings.name.detail") {
                HStack(spacing: Spacing.s2) {
                    WorkspaceBadge(initial: Workspace(name: name, location: .device).initial)
                    TextField("app:onboarding.name.placeholder", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)  // design-lint: allow (field width)
                        .onSubmit { model.renameWorkspace(name) }
                        .accessibilityIdentifier("settings-name")
                }
            }
            SettingsRow("app:settings.storage", detail: storageDetail) {
                EmptyView()
            }
        }
        .onAppear { name = model.workspace?.name ?? "" }
        // Saved when leaving the pane too, not only on Return.
        .onDisappear { model.renameWorkspace(name) }
    }

    private var storageDetail: LocalizedStringKey {
        switch model.workspace?.location {
        case .folder(_, let displayName): "app:settings.storage.folder \(displayName)"
        default: "app:onboarding.location.device"
        }
    }
}

private struct AboutPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsSection("app:settings.about") {
            SettingsRow("app:settings.version") {
                Text(verbatim: Self.version).font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
                    .textSelection(.enabled)
            }
            SettingsRow("app:settings.logs", detail: "app:settings.logs.detail") {
                ShareLink("app:workspace.exportLogs", items: model.exportableFiles)
                    .buttonStyle(.hikki(.outline))
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
