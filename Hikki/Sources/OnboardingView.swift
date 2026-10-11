import HikkiCore
import HikkiUI
import SwiftUI
import UniformTypeIdentifiers

/// First launch: welcome → name the workspace → choose where it lives (an iCloud Drive folder or
/// this device). Creates the workspace; the root view then switches to the app.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorTone) private var tone
    @State private var step: Step = .welcome
    @State private var name = OnboardingView.defaultName
    @State private var nameSelection: TextSelection?
    @FocusState private var nameFocused: Bool
    @State private var selectedSuggestion = false
    @State private var choice: Choice = .iCloud
    @State private var folder: (bookmark: Data, displayName: String)?
    @State private var importing = false
    @State private var errorMessage: String?

    private enum Step: Int, CaseIterable { case welcome, name, location }
    private enum Choice { case iCloud, device }

    var body: some View {
        VStack(spacing: Spacing.s8) {
            Group {
                switch step {
                case .welcome: welcome
                case .name: nameStep
                case .location: locationStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            StepDots(count: Step.allCases.count, current: step.rawValue)
        }
        .frame(maxWidth: 440)
        .padding(Spacing.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .animation(.snappy(duration: 0.25), value: step)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in pickFolder(result) }
        #if os(macOS)
            .background(WindowChrome())
            .ignoresSafeArea()
        #endif
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: Spacing.s5) {
            WorkspaceBadge(initial: "H", size: Size.onboardingBadge)
            Text("app:onboarding.welcome.title").font(.hk(.x3l, .bold)).foregroundStyle(Theme.foreground)
            Text("app:onboarding.welcome.subtitle")
                .font(.hk(.base))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
            Button("app:onboarding.start") { step = .name }
                .buttonStyle(.hikki(fullWidth: true))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-start")
                .padding(.top, Spacing.s3)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            header("app:onboarding.name.title", subtitle: "app:onboarding.name.subtitle")
            HStack(spacing: Spacing.s3) {
                WorkspaceBadge(initial: Workspace(name: name, location: .device).initial, size: Size.iconButton + Spacing.s3)
                TextField("app:onboarding.name.placeholder", text: $name, selection: $nameSelection)
                    .textFieldStyle(.plain)
                    .font(.hk(.lg, .medium))
                    .focused($nameFocused)
                    .onSubmit(continueFromName)
                    .accessibilityIdentifier("onboarding-name")
                if !name.isEmpty {
                    Button {
                        name = ""
                        nameFocused = true
                    } label: {
                        IconView(.x, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("app:onboarding.name.clear"))
                    .accessibilityIdentifier("onboarding-name-clear")
                }
            }
            .padding(Spacing.s3)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(nameFocused ? tone.fill : Theme.border))
            // The suggested name arrives focused and selected: typing replaces it, Return keeps it.
            .onAppear { nameFocused = true }
            .onChange(of: nameFocused) { _, focused in
                // Select once focus has landed — a selection set before that is dropped.
                guard focused, !selectedSuggestion else { return }
                selectedSuggestion = true
                nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
            }
            navigation(
                next: "app:onboarding.continue", id: "onboarding-continue", enabled: Workspace.normalizedName(name) != nil,
                action: continueFromName
            ) {
                step = .welcome
            }
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            header("app:onboarding.location.title", subtitle: "app:onboarding.location.subtitle")
            SelectableCard(
                "app:onboarding.location.icloud", detail: "app:onboarding.location.icloudDetail", icon: .cloud,
                isSelected: choice == .iCloud
            ) { choice = .iCloud }
            .accessibilityIdentifier("onboarding-icloud")
            if choice == .iCloud {
                HStack(spacing: Spacing.s2) {
                    IconView(.folderSimple, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                    // The folder path is shown as-is, never looked up as a localization key.
                    (folder.map { Text(verbatim: $0.displayName) } ?? Text("app:onboarding.location.noFolder"))
                        .font(.hk(.md))
                        .foregroundStyle(folder == nil ? Theme.mutedForeground : Theme.foreground)
                        .lineLimit(1)
                    Spacer()
                    Button(folder == nil ? "app:onboarding.location.chooseFolder" : "app:onboarding.location.changeFolder") {
                        importing = true
                    }
                    .buttonStyle(.hikki(.outline))
                    .accessibilityIdentifier("onboarding-choose-folder")
                }
                .padding(.horizontal, Spacing.s1)
            }
            SelectableCard(
                "app:onboarding.location.device", detail: "app:onboarding.location.deviceDetail", icon: .laptop,
                isSelected: choice == .device
            ) { choice = .device }
            .accessibilityIdentifier("onboarding-device")
            if let errorMessage {
                Text(LocalizedStringKey(errorMessage)).font(.hk(.md)).foregroundStyle(Theme.destructive)
            }
            navigation(next: "app:onboarding.create", id: "onboarding-create", enabled: choice == .device || folder != nil, action: create)
            {
                step = .name
            }
        }
    }

    // MARK: Pieces

    private func header(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1_5) {
            Text(title).font(.hk(.x2l, .bold)).foregroundStyle(Theme.foreground)
            Text(subtitle).font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
        }
        .padding(.bottom, Spacing.s2)
    }

    private func navigation(next: LocalizedStringKey, id: String, enabled: Bool, action: @escaping () -> Void, back: @escaping () -> Void)
        -> some View
    {
        HStack {
            Button("app:onboarding.back", action: back).buttonStyle(.hikki(.ghost))
            Spacer()
            Button(next, action: action)
                .buttonStyle(.hikki())
                .disabled(!enabled)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(id)
        }
        .padding(.top, Spacing.s2)
    }

    // MARK: Actions

    private func continueFromName() {
        guard Workspace.normalizedName(name) != nil else { return }
        step = .location
    }

    private func pickFolder(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            folder = (try FolderBookmark.make(for: url), FolderBookmark.displayName(for: url))
            errorMessage = nil
        } catch {
            Log.error("onboarding: folder pick failed: \(error)", category: "workspace")
            errorMessage = "app:onboarding.location.folderError"
        }
    }

    private func create() {
        guard let cleanName = Workspace.normalizedName(name) else { return }
        let location: Workspace.Location =
            if choice == .iCloud, let folder { .folder(bookmark: folder.bookmark, displayName: folder.displayName) } else { .device }
        model.createWorkspace(name: cleanName, location: location)
    }

    /// "Yancey’s Space" from the Mac's account name; a generic name elsewhere.
    static var defaultName: String {
        #if os(macOS)
            if let first = NSFullUserName().split(separator: " ").first, !first.isEmpty {
                return String(localized: "app:onboarding.name.default \(String(first))")
            }
        #endif
        return String(localized: "app:onboarding.name.fallback")
    }
}

/// Workspace initial on an accent tile (sidebar header, onboarding).
struct WorkspaceBadge: View {
    let initial: String
    var size: CGFloat = Size.iconButtonSm
    @Environment(\.colorTone) private var tone

    var body: some View {
        Text(initial)  // l10n: allow (a workspace initial)
            .font(.system(size: size * 0.55, weight: .bold))  // design-lint: allow (scales with the badge)
            .foregroundStyle(tone.onFill)
            .frame(width: size, height: size)
            .background(tone.fill.gradient, in: .rect(cornerRadius: size * 0.25))
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Spacing.s1_5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Theme.foreground : Theme.border)
                    .frame(width: index == current ? Spacing.s5 : Spacing.s1_5, height: Spacing.s1_5)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }
}
