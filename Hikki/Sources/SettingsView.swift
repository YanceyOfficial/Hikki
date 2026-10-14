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

/// The pages of Settings: toolbar tabs on the Mac (the classic Settings window), the hub list on iPhone and iPad.
enum SettingsPage: String, CaseIterable, Identifiable {
    case workspace, general, appearance, editor, shortcuts, search, ai, about

    /// The page Settings opens on, remembered; `HIKKI_OPEN_SETTINGS=<page>` sets it (screenshots).
    static let storageKey = "settings.page"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .workspace: "app:settings.workspace"
        case .general: "app:settings.general"
        case .appearance: "app:settings.appearance"
        case .editor: "app:settings.editor"
        case .shortcuts: "app:settings.shortcuts"
        case .search: "app:settings.search"
        case .ai: "app:settings.ai"
        case .about: "app:settings.about"
        }
    }

    var icon: Icon {
        switch self {
        case .workspace: .house
        case .general: .gearSix
        case .appearance: .slidersHorizontal
        case .editor: .pencilSimple
        case .shortcuts: .command
        case .search: .magnifyingGlass
        case .ai: .chatCircleDots
        case .about: .info
        }
    }

    /// The groups the iOS hub shows: the workspace, then the app, then About on its own.
    static let groups: [(title: LocalizedStringKey?, pages: [SettingsPage])] = [
        ("app:settings.group.workspace", [.workspace]),
        ("app:settings.group.app", [.general, .appearance, .editor, .shortcuts, .search, .ai]),
        (nil, [.about]),
    ]
}

/// Settings: pages as tabs (Mac) or a hub list (iPhone, iPad), each a grouped form of sections.
struct SettingsView: View {
    @AppStorage(SettingsPage.storageKey) private var pageID = SettingsPage.workspace.rawValue

    private var page: SettingsPage { SettingsPage(rawValue: pageID) ?? .workspace }

    var body: some View {
        content
            .environment(\.colorTone, ColorTone.standard)
            .tint(ColorTone.standard.fill)
    }

    #if os(macOS)
        /// The classic Mac Settings window: the pages as toolbar tabs along the top, a grouped form under each.
        private var content: some View {
            TabView(selection: Binding(get: { page }, set: { pageID = $0.rawValue })) {
                ForEach(SettingsPage.allCases) { page in
                    Tab(value: page) {
                        Form {
                            SettingsPageContent(page: page)
                        }
                        .formStyle(.grouped)
                    } label: {
                        Label {
                            Text(page.title)
                        } icon: {
                            page.icon.glyph
                        }
                    }
                    .accessibilityIdentifier("settings-page-\(page.rawValue)")
                }
            }
            .scenePadding()
            .frame(width: Size.settingsWidth)
            .frame(minHeight: Size.settingsHeight)
        }
    #else
        @Environment(\.dismiss) private var dismiss

        private var content: some View {
            NavigationStack {
                List {
                    ForEach(Array(SettingsPage.groups.enumerated()), id: \.offset) { _, group in
                        Section {
                            ForEach(group.pages) { page in
                                NavigationLink(value: page) {
                                    IconLabel(page.title, icon: page.icon)
                                }
                                .accessibilityIdentifier("settings-page-\(page.rawValue)")
                            }
                        } header: {
                            if let title = group.title { Text(title) }
                        }
                    }
                }
                .navigationTitle(Text("app:settings.title"))
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: SettingsPage.self) { page in
                    Form {
                        SettingsPageContent(page: page)
                    }
                    .navigationTitle(page.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { done }
                }
                .toolbar { done }
            }
        }

        private var done: some ToolbarContent {
            ToolbarItem(placement: .confirmationAction) {
                Button("app:settings.done") { dismiss() }
                    .accessibilityIdentifier("settings-close")
            }
        }
    #endif
}

/// One page's sections.
private struct SettingsPageContent: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .workspace:
            WorkspaceSection()
        case .general:
            LanguageSection()
            #if os(macOS)
                MenuBarSection()
            #endif
        case .appearance:
            AppearanceSection()
        case .editor:
            EditorSection()
        case .shortcuts:
            ShortcutsSection()
        case .ai:
            AISettingsSection()
        case .search:
            SemanticSection()
            SpotlightSection()
        case .about:
            AboutSection()
        }
    }
}

// MARK: - Sections

private struct WorkspaceSection: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var choosingFolder = false
    @State private var storageFailed = false
    @AppStorage(TrashPreferences.keepDaysKey) private var keepDays = TrashPreferences.defaultDays

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
        } footer: {
            Text("app:settings.icon.detail")
        }
        Section {
            LabeledContent("app:settings.storage.location") {
                HStack(spacing: Spacing.s2) {
                    storage
                    Button("app:settings.change") { choosingFolder = true }
                        .accessibilityIdentifier("settings-change-folder")
                }
            }
            if case .folder = model.workspace?.location {
                LabeledContent("app:settings.storage.sync") {
                    syncStatus
                        .foregroundStyle(model.syncError == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                        .accessibilityIdentifier("settings-sync-status")
                }
            }
        } header: {
            Text("app:settings.storage")
        } footer: {
            Text(storageFailed ? "app:settings.storage.error" : "app:settings.storage.detail")
                .foregroundStyle(storageFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
        Section {
            Picker("app:settings.trash.keep", selection: $keepDays) {
                ForEach(TrashPreferences.choices, id: \.self) { days in
                    if days == 0 {
                        Text("app:settings.trash.forever").tag(days)
                    } else {
                        Text("app:settings.trash.days \(days.formatted())").tag(days)
                    }
                }
            }
            .accessibilityIdentifier("settings-trash-keep")
            .onChange(of: keepDays) { _, _ in model.purgeTrash() }
        } header: {
            Text("app:settings.trash")
        } footer: {
            Text("app:settings.trash.detail")
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
            HStack(spacing: Spacing.s3) {
                WorkspaceBadge(initial: model.workspace?.initial ?? "H", icon: model.workspace?.icon, size: Size.iconButton)
                Menu("app:settings.change") {
                    Button("app:settings.icon.upload") { importing = true }
                    Button("app:settings.icon.emoji") { pickingEmoji = true }
                    if model.workspace?.icon != nil {
                        Divider()
                        Button("app:settings.icon.remove", role: .destructive) { model.setWorkspaceIcon(nil) }
                    }
                }
                .fixedSize()
                .accessibilityIdentifier("settings-icon-menu")
                .popover(isPresented: $pickingEmoji) { emojiGrid }
            }
        } label: {
            Text("app:settings.icon")
            if failed {
                Text("app:settings.icon.error").font(.caption).foregroundStyle(.red)
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

/// Settings → Shortcuts: every shortcut by group, each a key cap that records new keys (ShortcutStore). Keys another
/// shortcut has, the system's (⌘Q, ⌘C…) and plain keys are refused with the reason under the row.
private struct ShortcutsSection: View {
    private let store = ShortcutStore.shared
    @State private var recording: Shortcut?
    @State private var refusal: (shortcut: Shortcut, problem: KeyCombo.Problem)?
    @State private var query = ""
    @State private var confirmReset = false

    var body: some View {
        Section {
            TextField("app:shortcuts.search", text: $query)
                .accessibilityIdentifier("shortcuts-search")
        } footer: {
            Text("app:shortcuts.detail")
        }
        ForEach(Shortcut.Group.allCases, id: \.self) { group in
            let shortcuts = Shortcut.allCases.filter { $0.group == group && matches($0) }
            if !shortcuts.isEmpty {
                Section(group.title) {
                    ForEach(shortcuts, id: \.self) { shortcut in
                        row(shortcut)
                    }
                }
            }
        }
        Section {
            Button("app:shortcuts.resetAll", role: .destructive) { confirmReset = true }
                .disabled(store.overrides.combos.isEmpty)
                .accessibilityIdentifier("shortcuts-reset-all")
                .confirmationDialog("app:shortcuts.resetAll.confirm", isPresented: $confirmReset) {
                    Button("app:shortcuts.resetAll", role: .destructive) {
                        store.resetAll()
                        refusal = nil
                    }
                }
        }
    }

    private func row(_ shortcut: Shortcut) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            LabeledContent {
                ShortcutRecorder(
                    display: store.combo(shortcut).display,
                    isCustom: store.isCustom(shortcut),
                    recording: Binding(
                        get: { recording == shortcut },
                        set: { on in
                            if on {
                                recording = shortcut
                                refusal = nil
                            } else if recording == shortcut {
                                recording = nil
                            }
                        }),
                    identifier: "shortcut-\(shortcut.rawValue)",
                    onRecord: { key, modifiers in record(key, modifiers, for: shortcut) },
                    onReset: {
                        store.reset(shortcut)
                        refusal = nil
                    })
            } label: {
                Text(shortcut.title)
            }
            if let refusal, refusal.shortcut == shortcut {
                Text(message(refusal.problem))
                    .font(.hk(.xs))
                    .foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("shortcut-refusal")
            }
        }
    }

    private func record(_ key: KeyEquivalent, _ modifiers: EventModifiers, for shortcut: Shortcut) {
        guard let combo = KeyCombo(keyEquivalent: key, modifiers: modifiers) else { return }
        if let problem = store.problem(combo, for: shortcut) {
            refusal = (shortcut, problem)
        } else {
            store.set(combo, for: shortcut)
            refusal = nil
        }
    }

    private func message(_ problem: KeyCombo.Problem) -> String {
        switch problem {
        case .needsModifier: String(localized: "app:shortcuts.problem.needsModifier")
        case .unsupportedKey: String(localized: "app:shortcuts.problem.unsupported")
        case .reserved: String(localized: "app:shortcuts.problem.reserved")
        case .taken(let id):
            String(localized: "app:shortcuts.problem.taken \(Shortcut(rawValue: id).map { String(localized: $0.title) } ?? id)")
        }
    }

    /// The search matches the shortcut's name (in the app's language) or its keys ("⌘B", "b").
    private func matches(_ shortcut: Shortcut) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        let display = store.combo(shortcut).display
        return String(localized: shortcut.title).localizedCaseInsensitiveContains(needle)
            || display.localizedCaseInsensitiveContains(needle)
    }
}

/// Settings → Search → Semantic search: where the embedding model runs (Ollama on this Mac by default), which model,
/// an optional key, and how far the pages are embedded. Changes apply once typing in a field pauses.
private struct SemanticSection: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SemanticPreferences.enabledKey) private var enabled = false
    @AppStorage(SemanticPreferences.endpointKey) private var endpoint = SemanticPreferences.defaultEndpoint
    @AppStorage(SemanticPreferences.modelKey) private var modelName = SemanticPreferences.defaultModel
    /// The key for the address shown (keys are kept per origin).
    @State private var apiKey = ""
    @State private var available: [String] = []

    var body: some View {
        Section {
            Toggle("app:semantic.toggle", isOn: $enabled)
                .accessibilityIdentifier("settings-semantic")
            if enabled {
                TextField("app:semantic.endpoint", text: $endpoint, prompt: Text(verbatim: SemanticPreferences.defaultEndpoint))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings-semantic-endpoint")
                LabeledContent("app:semantic.model") {
                    HStack(spacing: Spacing.s2) {
                        TextField("app:semantic.model", text: $modelName, prompt: Text(verbatim: SemanticPreferences.defaultModel))
                            .labelsHidden()
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("settings-semantic-model")
                        if !available.isEmpty {
                            Menu {
                                ForEach(available, id: \.self) { name in
                                    Button(name) { modelName = name }
                                }
                            } label: {
                                Text("app:semantic.installed")
                            }
                            .fixedSize()
                            .accessibilityIdentifier("settings-semantic-installed")
                        }
                    }
                }
                SecureField("app:semantic.apiKey", text: $apiKey, prompt: Text("app:semantic.apiKey.prompt"))
                    .accessibilityIdentifier("settings-semantic-key")
                LabeledContent("app:semantic.status") {
                    Text(statusText).foregroundStyle(isFailing ? Theme.destructive : Theme.subtleForeground)
                        .accessibilityIdentifier("settings-semantic-status")
                }
            }
        } header: {
            Text("app:semantic.header")
        } footer: {
            Text("app:semantic.detail")
        }
        // Another address shows its own key (usually none): a key typed for one host never goes to another.
        .onChange(of: endpoint, initial: true) { _, address in
            apiKey = SemanticPreferences.apiKey(for: address) ?? ""
        }
        .onChange(of: apiKey) { _, key in
            // Stored under the address it was typed for.
            if let account = SemanticPreferences.apiKeyAccount(for: endpoint) {
                Keychain.write(key.trimmingCharacters(in: .whitespaces), for: account)
            }
        }
        .task(id: [String(enabled), endpoint, modelName, apiKey]) {
            // Once typing pauses: point the indexer at the new settings, list the endpoint's models.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.semantic.reconfigure()
            available = enabled ? ((try? await model.semantic.availableModels()) ?? []) : []
        }
    }

    private var isFailing: Bool {
        if case .failed = model.semantic.status { return true }
        return false
    }

    private var statusText: String {
        switch model.semantic.status {
        case .off: String(localized: "app:semantic.status.off")
        case .working(let done, let total): String(localized: "app:semantic.status.working \(done.formatted()) \(total.formatted())")
        case .ready(let pages): String(localized: "app:semantic.status.ready \(pages.formatted())")
        case .failed(.unreachable): String(localized: "app:semantic.error.unreachable")
        case .failed(.http(404)): String(localized: "app:semantic.error.noModel")
        case .failed(.http(let code)): String(localized: "app:semantic.error.http \(String(code))")
        case .failed(.badResponse): String(localized: "app:semantic.error.badResponse")
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
                HStack(spacing: Spacing.s2) {
                    Text(verbatim: Self.currentLanguage)
                    Button("app:settings.change", action: openLanguageSettings)
                        .accessibilityIdentifier("settings-language-change")
                }
            }
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
