import XCTest
@testable import WoWSiliconSwift

final class UserPrefsStoreTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testSaveAndLoadRoundTripsPreferences() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = UserPrefsStore(supportDirectory: supportURL)
        var prefs = UserPrefs.defaults
        prefs.remapOptionAsAlt = true
        prefs.wineBottlePath = "/Games/TestBottle"

        store.save(prefs)

        XCTAssertEqual(store.load(), prefs)
    }

    func testSavingUnchangedPreferencesDoesNotRewriteFile() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = UserPrefsStore(supportDirectory: supportURL)
        let prefs = UserPrefs.defaults
        let prefsURL = supportURL.appendingPathComponent("SiloWow/prefs.json")

        store.save(prefs)
        let originalModificationDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate],
            ofItemAtPath: prefsURL.path
        )

        store.save(prefs)

        let attributes = try FileManager.default.attributesOfItem(atPath: prefsURL.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, originalModificationDate)
    }

    func testCorruptPrefsFileIsKeptAsBackupAndNotOverwritten() throws {
        let supportURL = try makeTemporaryDirectory()
        let dir = supportURL.appendingPathComponent("SiloWow")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ broken".write(to: dir.appendingPathComponent("prefs.json"), atomically: true, encoding: .utf8)

        let store = UserPrefsStore(supportDirectory: supportURL)
        let report = store.loadWithReport()

        XCTAssertEqual(report.prefs, .defaults)
        let backup = try XCTUnwrap(report.corruptBackupURL)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("prefs.json.corrupt-"))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{ broken")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("prefs.json").path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
