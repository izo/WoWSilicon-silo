import XCTest
@testable import WoWSiliconSwift

final class ClientConfigWTFServiceTests: XCTestCase {
    private let sample = "SET portal \"US\"\nSET gxApi \"D3D12\"\nSET textLocale \"enUS\"\nSET Gamma \"1.0\"\nSET realmName \"Mon Royaume\"\n"

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testReplacesInPlaceAndKeepsOtherKeys() {
        let out = ClientConfigWTFService.updatedContent(sample, entries: [
            ("portal", "wow.ulk.me:1119"), ("gxApi", "D3D11"), ("textLocale", "frFR")
        ])
        XCTAssertEqual(
            out,
            "SET portal \"wow.ulk.me:1119\"\nSET gxApi \"D3D11\"\nSET textLocale \"frFR\"\nSET Gamma \"1.0\"\nSET realmName \"Mon Royaume\"\n"
        )
    }

    func testAppendsMissingKeysAndHandlesEmptyFile() {
        XCTAssertEqual(
            ClientConfigWTFService.updatedContent("SET Gamma \"1.0\"\n", entries: [("audioLocale", "frFR")]),
            "SET Gamma \"1.0\"\nSET audioLocale \"frFR\"\n"
        )
        XCTAssertEqual(
            ClientConfigWTFService.updatedContent("SET Gamma \"1.0\"", entries: [("audioLocale", "frFR")]),
            "SET Gamma \"1.0\"\nSET audioLocale \"frFR\"\n"
        )
        XCTAssertEqual(ClientConfigWTFService.updatedContent("", entries: [("portal", "a.b")]), "SET portal \"a.b\"\n")
    }

    func testKeyMatchIgnoresCaseAndKeepsWindowsLineEndings() {
        let out = ClientConfigWTFService.updatedContent("set GXAPI \"D3D12\"\r\nSET Gamma \"1.0\"\r\n", entries: [("gxApi", "D3D11")])
        XCTAssertEqual(out, "SET gxApi \"D3D11\"\r\nSET Gamma \"1.0\"\r\n")
    }

    func testRefusesValuesThatCouldInjectLines() {
        XCTAssertTrue(ClientConfigWTFService.isValidPortal("wow.ulk.me:1119"))
        XCTAssertFalse(ClientConfigWTFService.isValidPortal("a.b\"\nSET x \"1"))
        XCTAssertFalse(ClientConfigWTFService.isValidPortal("a b"))
        XCTAssertFalse(ClientConfigWTFService.isValidPortal(""))
        XCTAssertTrue(ClientConfigWTFService.isValidLocale("frFR"))
        XCTAssertFalse(ClientConfigWTFService.isValidLocale("frFR\"\nSET x \"1"))
        XCTAssertFalse(ClientConfigWTFService.isValidLocale("fr"))
        // Even called directly, updatedContent never writes an unsafe value or key.
        let evil = ClientConfigWTFService.updatedContent(sample, entries: [
            ("textLocale", "frFR\"\nSET evil \"1"), ("bad key", "x"), ("a\nb", "x")
        ])
        XCTAssertEqual(evil, sample)
    }

    func testEntriesFollowSettings() {
        let none = ClientConfigWTFService.entries(for: VersionSettings())
        XCTAssertEqual(none.map(\.key), ["gxApi"])
        XCTAssertEqual(none.first?.value, "D3D11")
        let full = ClientConfigWTFService.entries(for: VersionSettings(portal: " h:1 ", textLocale: "frFR", audioLocale: "enUS"))
        XCTAssertEqual(full.map(\.key), ["portal", "gxApi", "textLocale", "audioLocale"])
        XCTAssertEqual(full.map(\.value), ["h:1", "D3D11", "frFR", "enUS"])
        let invalid = ClientConfigWTFService.entries(for: VersionSettings(portal: "a b", textLocale: "xx"))
        XCTAssertEqual(invalid.map(\.key), ["gxApi"])
    }

    func testApplyCreatesFileIsIdempotentAndKeepsOtherKeys() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = VersionSettings(portal: "wow.ulk.me:1119", textLocale: "frFR")
        try ClientConfigWTFService.apply(settings: settings, gameURL: dir)
        let url = dir.appendingPathComponent("WTF/Config.wtf")
        let created = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(created, "SET portal \"wow.ulk.me:1119\"\nSET gxApi \"D3D11\"\nSET textLocale \"frFR\"\n")

        try (created + "SET Gamma \"1.0\"\n").write(to: url, atomically: true, encoding: .utf8)
        try ClientConfigWTFService.apply(settings: settings, gameURL: dir)
        try ClientConfigWTFService.apply(settings: settings, gameURL: dir)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), created + "SET Gamma \"1.0\"\n")

        try ClientConfigWTFService.apply(settings: VersionSettings(portal: "other.host:1119", textLocale: "deDE"), gameURL: dir)
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8),
            "SET portal \"other.host:1119\"\nSET gxApi \"D3D11\"\nSET textLocale \"deDE\"\nSET Gamma \"1.0\"\n"
        )
    }

    func testLatin1ConfigKeepsOtherKeysAndEncoding() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("WTF/Config.wtf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "SET portal \"US\"\nSET realmName \"Royaume d\u{E9}j\u{E0}\"\nSET Gamma \"1.0\"\n"
        let bytes = try XCTUnwrap(original.data(using: .isoLatin1))
        XCTAssertNil(String(data: bytes, encoding: .utf8), "fixture must not be valid UTF-8")
        try bytes.write(to: url)

        try ClientConfigWTFService.apply(settings: VersionSettings(portal: "wow.ulk.me:1119"), gameURL: dir)

        let written = try Data(contentsOf: url)
        let text = try XCTUnwrap(String(data: written, encoding: .isoLatin1))
        XCTAssertEqual(
            text,
            "SET portal \"wow.ulk.me:1119\"\nSET realmName \"Royaume d\u{E9}j\u{E0}\"\nSET Gamma \"1.0\"\nSET gxApi \"D3D11\"\n"
        )
    }

    func testUnreadableConfigIsNeverReplaced() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A directory where the file should be: it exists but cannot be read as a file.
        let url = dir.appendingPathComponent("WTF/Config.wtf")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ClientConfigWTFService.apply(settings: VersionSettings(), gameURL: dir)) { error in
            guard case ClientConfigWTFService.ConfigError.unreadable = error else {
                return XCTFail("Expected an unreadable error, got \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("untouched"))
        }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    func testEmptyLocaleLeavesExistingLocaleAlone() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("WTF/Config.wtf")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "SET textLocale \"esES\"\n".write(to: url, atomically: true, encoding: .utf8)
        try ClientConfigWTFService.apply(settings: VersionSettings(), gameURL: dir)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "SET textLocale \"esES\"\nSET gxApi \"D3D11\"\n")
    }

    func testSettingsWithoutNewKeysDecodeToEmpty() throws {
        let settings = try JSONDecoder().decode(VersionSettings.self, from: Data("{\"cursorSizeMultiplier\":2}".utf8))
        XCTAssertEqual(settings.portal, "")
        XCTAssertEqual(settings.textLocale, "")
        XCTAssertEqual(settings.audioLocale, "")
        XCTAssertEqual(settings.cursorSizeMultiplier, 2)
        let roundTrip = try JSONDecoder().decode(
            VersionSettings.self,
            from: JSONEncoder().encode(VersionSettings(portal: "h:1", textLocale: "frFR", audioLocale: "enGB"))
        )
        XCTAssertEqual(roundTrip.portal, "h:1")
        XCTAssertEqual(roundTrip.textLocale, "frFR")
        XCTAssertEqual(roundTrip.audioLocale, "enGB")
    }
}
