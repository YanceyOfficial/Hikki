import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// A fenced code block in read-only text (the AI chat's answers): a strip with the language and a copy button over the
/// code in a monospaced font, scrolling sideways rather than wrapping, on a quiet fill. `highlighted` is the code
/// already coloured (the caller's highlighter); plain `code` until it arrives. After exodus-ios's
/// `MarkdownCodeBlockView` (Sources/MarkdownKit), drawn with Hikki's tokens on both platforms.
public struct CodeBlockView: View {
    private let code: String
    private let language: String?
    private let highlighted: AttributedString?
    private let copyLabel: LocalizedStringKey
    private let copiedLabel: LocalizedStringKey
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    /// `language` as the fence names it (shown by its usual name: "ts" → TypeScript); `copyLabel` / `copiedLabel` are
    /// what VoiceOver reads for the copy button before and after a copy.
    public init(
        code: String, language: String?, highlighted: AttributedString? = nil, copyLabel: LocalizedStringKey,
        copiedLabel: LocalizedStringKey
    ) {
        self.code = code
        self.language = language
        self.highlighted = highlighted
        self.copyLabel = copyLabel
        self.copiedLabel = copiedLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            HStack(spacing: Spacing.s1_5) {
                IconView(.code, size: TextSize.xs.rawValue).foregroundStyle(Theme.mutedForeground)
                Text(verbatim: CodeLanguageName.display(language ?? "text"))
                    .font(.hk(.xs, .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s2)
                // The icon alone in a box of one size, so the strip never shifts; the words are for VoiceOver.
                Button(action: copy) {
                    IconLabel(copied ? copiedLabel : copyLabel, icon: copied ? .check : .copy, size: TextSize.sm.rawValue)
                        .labelStyle(.iconOnly)
                        .frame(width: Size.iconButton, height: Size.iconButton)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.mutedForeground)
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.leading, Spacing.s3)
            .padding(.trailing, Spacing.s1_5)
            .padding(.vertical, Spacing.s1)

            ScrollView(.horizontal) {
                Text(highlighted ?? AttributedString(code))
                    .font(.hk(.md, design: .monospaced))
                    .foregroundStyle(Theme.foreground)
                    .lineSpacing(Spacing.s0_5)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.bottom, Spacing.s3)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .trailingScrollFade()
        }
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func copy() {
        #if os(iOS)
            UIPasteboard.general.string = code
        #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
        #endif
        withAnimation(Motion.easeOut()) { copied = true }
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.easeOut()) { copied = false }
        }
    }
}

/// The name a code block's language is shown under — `TypeScript`, not the fence's `ts` (exodus-ios's
/// `MarkdownLanguageName` table). An unknown name keeps its spelling with a capital first letter.
public enum CodeLanguageName {
    public static func display(_ id: String) -> String {
        let key = id.trimmingCharacters(in: .whitespaces).lowercased()
        if let known = names[key] { return known }
        guard let first = key.first else { return "" }
        return first.uppercased() + key.dropFirst()
    }

    private static let names: [String: String] = [
        "bash": "Bash", "c": "C", "c++": "C++", "cpp": "C++", "cs": "C#", "csharp": "C#", "css": "CSS",
        "dart": "Dart", "diff": "Diff", "dockerfile": "Dockerfile", "docker": "Dockerfile", "elixir": "Elixir",
        "erlang": "Erlang", "go": "Go", "golang": "Go", "graphql": "GraphQL", "groovy": "Groovy",
        "haskell": "Haskell", "hs": "Haskell", "html": "HTML", "http": "HTTP", "ini": "INI", "java": "Java",
        "javascript": "JavaScript", "js": "JavaScript", "json": "JSON", "json5": "JSON5", "jsonc": "JSON",
        "jsx": "JSX", "kotlin": "Kotlin", "kt": "Kotlin", "latex": "LaTeX", "tex": "LaTeX", "less": "Less",
        "lua": "Lua", "makefile": "Makefile", "make": "Makefile", "markdown": "Markdown", "md": "Markdown",
        "mermaid": "Mermaid", "nginx": "Nginx", "objc": "Objective-C", "objectivec": "Objective-C",
        "objective-c": "Objective-C", "ocaml": "OCaml", "perl": "Perl", "php": "PHP", "plaintext": "Text",
        "text": "Text", "txt": "Text", "powershell": "PowerShell", "ps1": "PowerShell", "pwsh": "PowerShell",
        "proto": "Protobuf", "protobuf": "Protobuf", "py": "Python", "python": "Python", "r": "R", "rb": "Ruby",
        "ruby": "Ruby", "rs": "Rust", "rust": "Rust", "scala": "Scala", "scss": "SCSS", "sass": "Sass",
        "sh": "Shell", "shell": "Shell", "zsh": "Zsh", "fish": "Fish", "console": "Console",
        "shell-session": "Console", "sql": "SQL", "postgres": "PostgreSQL", "postgresql": "PostgreSQL",
        "mysql": "MySQL", "sqlite": "SQLite", "svelte": "Svelte", "swift": "Swift", "toml": "TOML",
        "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TSX", "vue": "Vue", "wasm": "WebAssembly",
        "xml": "XML", "yaml": "YAML", "yml": "YAML", "zig": "Zig",
    ]
}

/// Fades the trailing edge of a sideways scroll view while more lies to the right — the only hint that a long code
/// line or a wide table scrolls (exodus-ios's `MarkdownTrailingFade`).
struct TrailingScrollFade: ViewModifier {
    @State private var moreToRight = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.width - geometry.contentOffset.x - geometry.containerSize.width > 1
            } action: { _, more in
                moreToRight = more
            }
            .mask {
                HStack(spacing: Spacing.s0) {
                    Rectangle()
                    LinearGradient(colors: [.black, moreToRight ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Spacing.s7)
                }
            }
    }
}

extension View {
    func trailingScrollFade() -> some View { modifier(TrailingScrollFade()) }
}

#Preview {
    VStack(spacing: Spacing.s4) {
        CodeBlockView(
            code:
                "func greet(_ name: String) -> String {\n    // A very long line that scrolls sideways rather than wrapping in the block\n    \"Hello, \\(name)\"\n}",
            language: "swift", copyLabel: "Copy code", copiedLabel: "Copied")
        CodeBlockView(code: "$ make check", language: nil, copyLabel: "Copy code", copiedLabel: "Copied")
    }
    .padding(Spacing.s6)
    .frame(width: 420)
}
