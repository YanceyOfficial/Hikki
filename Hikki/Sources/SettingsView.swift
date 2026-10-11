import HikkiCore
import HikkiUI
import SwiftUI

/// Device-level appearance choice (Settings → Appearance → Theme), applied at the root of each window.
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

/// Settings in Apple's own style: native grouped forms. macOS gets a Settings window with toolbar tabs
/// (like Safari or Notes, opened with ⌘,); iPhone and iPad get an inset-grouped form in a sheet.
struct SettingsView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        content.preferredColorScheme(appearance.colorScheme)
    }

    #if os(macOS)
        private var content: some View {
            TabView {
                Tab {
                    Form {
                        WorkspaceSection()
                        LanguageSection()
                    }
                    .formStyle(.grouped)
                } label: {
                    Label {
                        Text("app:settings.general")
                    } icon: {
                        Icon.gearSix.glyph
                    }
                }
                Tab {
                    Form { AppearanceSection() }.formStyle(.grouped)
                } label: {
                    Label {
                        Text("app:settings.appearance")
                    } icon: {
                        Icon.slidersHorizontal.glyph
                    }
                }
                Tab {
                    Form { AboutSection() }.formStyle(.grouped)
                } label: {
                    Label {
                        Text("app:settings.about")
                    } icon: {
                        Icon.info.glyph
                    }
                }
            }
            .scenePadding()
            .frame(width: 520)  // design-lint: allow (Settings window width, like Apple's apps)
            .frame(minHeight: 280)  // design-lint: allow
        }
    #else
        @Environment(\.dismiss) private var dismiss

        private var content: some View {
            NavigationStack {
                Form {
                    WorkspaceSection()
                    AppearanceSection()
                    LanguageSection()
                    AboutSection()
                }
                .navigationTitle(Text("app:settings.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("app:settings.done") { dismiss() }
                            .accessibilityIdentifier("settings-close")
                    }
                }
            }
        }
    #endif
}

// MARK: - Sections

private struct WorkspaceSection: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        Section {
            LabeledContent("app:settings.name") {
                TextField("app:onboarding.name.placeholder", text: $name)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .onSubmit { model.renameWorkspace(name) }
                    .accessibilityIdentifier("settings-name")
            }
            LabeledContent("app:settings.storage") {
                storage
            }
        } header: {
            Text("app:settings.group.workspace")
        }
        .onAppear { name = model.workspace?.name ?? "" }
        // Saved when Settings closes too, not only on Return.
        .onDisappear { model.renameWorkspace(name) }
        .onChange(of: model.workspace?.name) { _, current in
            if let current, current != name { name = current }
        }
    }

    @ViewBuilder private var storage: some View {
        switch model.workspace?.location {
        case .folder(_, let displayName): Text(verbatim: displayName)  // the folder path, as-is
        default: Text("app:onboarding.location.device")
        }
    }
}

private struct AppearanceSection: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        Section {
            Picker("app:settings.theme", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings-theme")
        } header: {
            Text("app:settings.appearance")
        } footer: {
            Text("app:settings.theme.detail")
        }
    }
}

private struct LanguageSection: View {
    var body: some View {
        Section {
            LabeledContent("app:settings.language") {
                Text(verbatim: Self.currentLanguage)
            }
            Button("app:settings.language.open", action: openLanguageSettings)
        } footer: {
            Text("app:settings.language.detail")
        }
    }

    /// The language the app is running in, named in that language (e.g. "English", "简体中文").
    private static var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: code).localizedString(forIdentifier: code)?.localizedCapitalized ?? code
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

private struct AboutSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("app:settings.version") {
                Text(verbatim: Self.version).textSelection(.enabled)
            }
            ShareLink("app:workspace.exportLogs", items: model.exportableFiles)
        } header: {
            Text("app:settings.about")
        } footer: {
            Text("app:settings.logs.detail")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
