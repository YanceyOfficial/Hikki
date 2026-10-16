// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    // GRDB as one dynamic framework: HikkiCore and HikkiSearch both use it, and a static library would be linked into
    // each (two copies of GRDB and its Swift metadata in one process).
    // It stays its own framework in Release too: marked mergeable (it lives in Tuist's generated package project),
    // the app's merged binary looked for GRDB's symbols in a stub that no longer had them and failed at launch.
    let packageSettings = PackageSettings(productTypes: ["GRDB": .framework])
#endif

let package = Package(
    name: "HikkiDependencies",
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1")
    ]
)
