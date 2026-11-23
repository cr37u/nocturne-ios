import XCTest

/// Launches the app with demo data on the current simulator and saves screenshots of the main
/// screens. CI runs it on iPhone SE (3rd gen), iPhone 14, iPhone 15 Pro and iPhone 16 Pro Max and
/// uploads the PNGs, so the per-device layouts can be checked without a Mac.
final class ScreenshotTests: XCTestCase {
    private let screens: [(String, [String])] = [
        ("01-Biblioteca", []),
        ("02-SeRedaAcum", ["-demoScreen", "nowPlaying"]),
        ("03-Playlisturi", ["-demoScreen", "playlists"]),
        ("04-Descarcari", ["-demoScreen", "downloads"]),
        ("05-Adauga", ["-demoScreen", "add"]),
        ("06-Setari", ["-demoScreen", "settings"]),
        ("07-Library-EN", ["-demoLanguage", "en"]),
        ("08-NowPlaying-RU", ["-demoScreen", "nowPlaying", "-demoLanguage", "ru"]),
    ]

    override func setUp() {
        continueAfterFailure = true
    }

    func testCaptureMainScreens() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
            ?? ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "device"
        let outDir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"]
        for (name, args) in screens {
            let app = XCUIApplication()
            app.launchArguments = ["-demoData"] + args
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            sleep(2)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(device)-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if let outDir {
                let safeDevice = device.replacingOccurrences(of: " ", with: "_")
                let dir = URL(fileURLWithPath: outDir).appendingPathComponent(safeDevice, isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
            }
            app.terminate()
        }
    }
}
