#if os(iOS)
    import XCTest

    /// Not a regression test: one screenshot for the website or the App Store, taken on its side — an iPad's layout is
    /// landscape, and `simctl` can't turn a simulator. Runs only when the runner gets HIKKI_SHOT (where to save the
    /// PNG); `design/store/shoot.sh --landscape` passes it and the rest as `TEST_RUNNER_` variables: HIKKI_SHOT_DATA
    /// (the demo workspace's data folder), HIKKI_SHOT_ENV (the app's hooks, `KEY=value|KEY=value`), HIKKI_SHOT_WAIT
    /// (seconds before the picture).
    @MainActor
    final class StoreScreenshot: XCTestCase {
        func testTakeScreenshot() throws {
            let environment = ProcessInfo.processInfo.environment
            guard let out = environment["HIKKI_SHOT"], let data = environment["HIKKI_SHOT_DATA"] else {
                throw XCTSkip("screenshots only")
            }
            XCUIDevice.shared.orientation = .landscapeLeft
            let app = XCUIApplication()
            app.launchEnvironment["HIKKI_DATA_DIR"] = data
            app.launchEnvironment["HIKKI_WORKSPACE"] = "Personal"
            app.launchEnvironment["HIKKI_FRESH_TABS"] = "1"
            app.launchArguments += ["-AppleLanguages", "(\(environment["HIKKI_SHOT_LANGUAGE"] ?? "en"))"]
            // The first launch imports the workspace's page files; the hooks need the pages to be there.
            app.launch()
            sleep(8)
            app.terminate()
            for pair in (environment["HIKKI_SHOT_ENV"] ?? "").split(separator: "|") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                app.launchEnvironment[parts[0]] = parts.count > 1 ? parts[1] : "1"
            }
            app.launch()
            sleep(UInt32(environment["HIKKI_SHOT_WAIT"] ?? "14") ?? 14)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: out))
        }
    }
#endif
