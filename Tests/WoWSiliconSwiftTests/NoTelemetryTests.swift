import XCTest
@testable import WoWSiliconSwift

final class NoTelemetryTests: XCTestCase {
    func testLegacyPrefsWithTelemetryKeysStillDecodeAndAreNotWrittenBack() throws {
        let legacy = #"""
        {"remap_option_as_alt": true, "telemetry_enabled": true,
         "telemetry_consent_asked": true, "telemetry_install_id": "abc"}
        """#
        let prefs = try JSONDecoder().decode(UserPrefs.self, from: Data(legacy.utf8))
        XCTAssertTrue(prefs.remapOptionAsAlt)

        let encoded = try JSONEncoder().encode(prefs)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("telemetry"))
        XCTAssertFalse(text.contains("abc"))
    }

    /// No network send is possible: the sources contain neither the telemetry endpoint nor a telemetry type.
    func testSourcesContainNoTelemetryEndpointOrClient() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/WoWSiliconSwift", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let content = try String(contentsOf: url, encoding: .utf8).lowercased()
            scanned += 1
            XCTAssertFalse(content.contains("workers.dev"), url.lastPathComponent)
            XCTAssertFalse(content.contains("telemetry"), url.lastPathComponent)
        }
        XCTAssertGreaterThan(scanned, 20)
    }
}
