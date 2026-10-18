// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    // GRDB as one dynamic framework: HikkiCore and HikkiSearch both use it, and a static library would be linked into
    // each (two copies of GRDB and its Swift metadata in one process).
    // It stays its own framework in Release too: marked mergeable (it lives in Tuist's generated package project),
    // the app's merged binary looked for GRDB's symbols in a stub that no longer had them and failed at launch.
    // swift-markdown and HighlightSwift are linked by HikkiAI alone (the chat's answers): static frameworks inside it.
    let packageSettings = PackageSettings(productTypes: [
        "GRDB": .framework, "Markdown": .staticFramework, "HighlightSwift": .staticFramework,
    ])
#endif

let package = Package(
    name: "HikkiDependencies",
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        // The chat's answers as Markdown: cmark-gfm's tree (tables, fences, lists), as exodus-ios renders them.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        // highlight.js in JavaScriptCore — the tokenizer behind the editor's code blocks (lowlight), so both colour alike.
        .package(url: "https://github.com/appstefan/HighlightSwift.git", exact: "1.1.0"),
    ]
)
