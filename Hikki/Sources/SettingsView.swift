import HikkiCore
import HikkiUI
import SwiftUI
import UniformTypeIdentifiers

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

    /// Applies it app-wide. `preferredColorScheme` isn't reliable for this: once a scheme has been forced,
    /// going back (to light, or to "system") left parts of windows — Settings, the toolbar — in the old one.
    /// The app-level appearance switches every window, the editor's web view included, at once.
    @MainActor func apply() {
        #if os(macOS)
            NSApp.appearance =
                switch self {
                case .system: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
        #else
            let style: UIUserInterfaceStyle =
                switch self {
                case .system: .unspecified
                case .light: .light
                case .dark: .dark
                }
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                for window in scene.windows { window.overrideUserInterfaceStyle = style }
            }
        #endif
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
        content
            .environment(\.colorTone, ColorTone.standard)
            .tint(ColorTone.standard.fill)
    }

    #if os(macOS)
        private var content: some View {
            TabView {
                Tab {
                    Form {
                        WorkspaceSection()
                        EditorSection()
                        SpotlightSection()
                        MenuBarSection()
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
                    Form {
                        AppearanceSection()
                    }
                    .formStyle(.grouped)
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
                    EditorSection()
                    SpotlightSection()
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
    @State private var choosingFolder = false
    @State private var storageFailed = false

    var body: some View {
        Section {
            LabeledContent("app:settings.name") {
                TextField("app:onboarding.name.placeholder", text: $name)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                    .onSubmit { model.renameWorkspace(name) }
                    .accessibilityIdentifier("settings-name")
            }
            WorkspaceIconRow()
            LabeledContent {
                HStack(spacing: Spacing.s2) {
                    storage
                    Button("app:settings.storage.change") { choosingFolder = true }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("settings-change-folder")
                }
            } label: {
                Text("app:settings.storage")
                Text(storageFailed ? "app:settings.storage.error" : "app:settings.storage.detail")
                    .font(.caption)
                    .foregroundStyle(storageFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                if case .folder = model.workspace?.location {
                    syncStatus
                        .font(.caption)
                        .foregroundStyle(model.syncError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        .accessibilityIdentifier("settings-sync-status")
                }
            }
        } header: {
            Text("app:settings.group.workspace")
        }
        // Moving to (or joining) a folder — put it in iCloud Drive to use the workspace on other devices.
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            do {
                try model.changeLocation(to: try result.get())
                storageFailed = false
            } catch {
                Log.error("settings: change folder failed: \(error)", category: "workspace")
                storageFailed = true
            }
        }
        .onAppear { name = model.workspace?.name ?? "" }
        // Saved when Settings closes too, not only on Return.
        .onDisappear { model.renameWorkspace(name) }
        .onChange(of: model.workspace?.name) { _, current in
            if let current, current != name { name = current }
        }
    }

    /// When the folder was last reconciled, and what's still on its way ("2 waiting for iCloud").
    /// Always says something for a folder: not yet, why not, or when and what is still on its way.
    private var syncStatus: Text {
        if let error = model.syncError { return Text("app:settings.storage.syncError \(error)") }
        guard let sync = model.lastSync else { return Text("app:settings.storage.notSynced") }
        var text = Text("app:settings.storage.synced \(sync.at, format: .relative(presentation: .named))")
        if sync.report.waitingForDownload > 0 {
            text = text + Text(verbatim: " · ") + Text("app:settings.storage.waiting \(sync.report.waitingForDownload.formatted())")
        }
        if sync.report.skippedFiles > 0 {
            text = text + Text(verbatim: " · ") + Text("app:settings.storage.skipped \(sync.report.skippedFiles.formatted())")
        }
        return text
    }
    @ViewBuilder private var storage: some View {
        switch model.workspace?.location {
        case .folder(_, let displayName): Text(verbatim: displayName)  // the folder path, as-is
        default: Text("app:onboarding.location.device")
        }
    }
}

/// Settings → General → Icon (Notion): upload an image, pick an emoji, or go back to the initial.
private struct WorkspaceIconRow: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var pickingEmoji = false
    @State private var failed = false

    private static let emoji = [
        "🏠", "📓", "📚", "🗂️", "✏️", "🖋️", "🧠", "💡", "🚀", "🌱", "🌸", "🍀", "🌊", "🔥", "⭐️", "🌙",
        "☕️", "🍵", "🎧", "🎨", "📷", "🧭", "🗻", "🏔️", "🏯", "⛩️", "🎌", "🐱", "🦊", "🐼", "🐳", "🦉",
    ]

    var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.s2) {
                Button("app:settings.icon.upload") { importing = true }
                Button("app:settings.icon.emoji") { pickingEmoji = true }
                    .popover(isPresented: $pickingEmoji) { emojiGrid }
                if model.workspace?.icon != nil {
                    Button("app:settings.icon.remove", role: .destructive) { model.setWorkspaceIcon(nil) }
                }
            }
            // Borderless: in an iOS form row, plain buttons would all fire on one tap.
            .buttonStyle(.borderless)
        } label: {
            HStack(spacing: Spacing.s3) {
                WorkspaceBadge(initial: model.workspace?.initial ?? "H", icon: model.workspace?.icon, size: Size.iconButton + Spacing.s3)
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text("app:settings.icon")
                    Text(failed ? "app:settings.icon.error" : "app:settings.icon.detail")
                        .font(.caption)
                        .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let thumbnail = WorkspaceIcon.thumbnail(of: data) {
                failed = false
                model.setWorkspaceIcon(.image(thumbnail))
            } else {
                failed = true
            }
        }
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Size.iconButton + Spacing.s2)), count: 8), spacing: Spacing.s1) {
            ForEach(Self.emoji, id: \.self) { emoji in
                Button {
                    model.setWorkspaceIcon(.emoji(emoji))
                    pickingEmoji = false
                } label: {
                    Text(verbatim: emoji)
                        .font(.title2)
                        .frame(width: Size.iconButton + Spacing.s2, height: Size.iconButton + Spacing.s2)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.s3)
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

/// Editor preferences (stored in UserDefaults, sent to the editor by ContentView).
enum EditorPreferences {
    static let spellcheckKey = "editor.spellcheck"
}

private struct EditorSection: View {
    @AppStorage(EditorPreferences.spellcheckKey) private var spellcheck = true

    var body: some View {
        Section {
            Toggle("app:settings.spellcheck", isOn: $spellcheck)
                .accessibilityIdentifier("settings-spellcheck")
        } header: {
            Text("app:settings.editor")
        } footer: {
            Text("app:settings.spellcheck.detail")
        }
    }
}

/// Settings → Spotlight: pages in the device's Spotlight index (SpotlightIndex.swift).
private struct SpotlightSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SpotlightPreferences.enabledKey) private var enabled = true

    var body: some View {
        Section {
            Toggle("app:settings.spotlight", isOn: $enabled)
                .accessibilityIdentifier("settings-spotlight")
                .onChange(of: enabled) { _, on in model.searchIndexer.setSpotlight(enabled: on) }
        } header: {
            Text("app:settings.spotlight.header")
        } footer: {
            Text("app:settings.spotlight.detail")
        }
    }
}

#if os(macOS)
    /// Settings → General → Menu bar: the status item is optional (MenuBarExtra.swift).
    private struct MenuBarSection: View {
        @AppStorage(MenuBarPreferences.showKey) private var show = true

        var body: some View {
            Section {
                Toggle("app:settings.menuBar", isOn: $show)
                    .accessibilityIdentifier("settings-menubar")
            } header: {
                Text("app:settings.menuBar.header")
            } footer: {
                Text("app:settings.menuBar.detail")
            }
        }
    }
#endif

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
