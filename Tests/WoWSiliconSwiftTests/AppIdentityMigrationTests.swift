import XCTest
@testable import WoWSiliconSwift

final class AppIdentityMigrationTests: XCTestCase {
    private var temp: [URL] = []

    override func tearDownWithError() throws {
        temp.forEach { try? FileManager.default.removeItem(at: $0) }
        temp.removeAll()
        try super.tearDownWithError()
    }

    private func makeSupport() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temp.append(url)
        return url
    }

    func testCopiesLegacySupportDirectoryOnceAndKeepsOriginal() throws {
        let support = try makeSupport()
        let legacy = support.appendingPathComponent("WoWSilicon", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("v1".utf8).write(to: legacy.appendingPathComponent("prefs.json"))
        try Data("x".utf8).write(to: legacy.appendingPathComponent("sub/file"))

        XCTAssertTrue(AppIdentityMigration.copyLegacySupportDirectoryIfNeeded(supportURL: support))

        let current = support.appendingPathComponent("SiloWow", isDirectory: true)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("prefs.json")), Data("v1".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("sub/file").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("prefs.json").path))

        // Second run: later edits on either side are never overwritten.
        try Data("v2".utf8).write(to: current.appendingPathComponent("prefs.json"))
        try Data("v3".utf8).write(to: legacy.appendingPathComponent("prefs.json"))
        XCTAssertFalse(AppIdentityMigration.copyLegacySupportDirectoryIfNeeded(supportURL: support))
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("prefs.json")), Data("v2".utf8))
    }

    func testDoesNothingWithoutLegacyDirectoryOrWhenCurrentExists() throws {
        let support = try makeSupport()
        XCTAssertFalse(AppIdentityMigration.copyLegacySupportDirectoryIfNeeded(supportURL: support))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("SiloWow").path))

        try FileManager.default.createDirectory(at: support.appendingPathComponent("WoWSilicon"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support.appendingPathComponent("SiloWow"), withIntermediateDirectories: true)
        XCTAssertFalse(AppIdentityMigration.copyLegacySupportDirectoryIfNeeded(supportURL: support))
    }

    func testStoresUseTheNewDirectoryName() throws {
        let support = try makeSupport()
        UserPrefsStore(supportDirectory: support).save(.defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("SiloWow/prefs.json").path))
    }

    func testMigratesSparkleAndUIDefaultsOnceWithoutOverwriting() throws {
        let suite = "silowow.tests.\(UUID().uuidString)"
        let current = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { current.removePersistentDomain(forName: suite) }
        current.set("kept", forKey: "SUSkippedVersion")

        let legacy: [String: Any] = [
            "SUSkippedVersion": "9.9.9",
            "SUAutomaticallyUpdate": true,
            "realmlistEditorMode": "raw",
            "unrelated": "no"
        ]
        XCTAssertEqual(AppIdentityMigration.migrateLegacyDefaultsIfNeeded(current: current, legacyValues: legacy), 2)
        XCTAssertEqual(current.string(forKey: "SUSkippedVersion"), "kept")
        XCTAssertTrue(current.bool(forKey: "SUAutomaticallyUpdate"))
        XCTAssertEqual(current.string(forKey: "realmlistEditorMode"), "raw")
        XCTAssertNil(current.object(forKey: "unrelated"))

        current.removeObject(forKey: "SUAutomaticallyUpdate")
        XCTAssertEqual(AppIdentityMigration.migrateLegacyDefaultsIfNeeded(current: current, legacyValues: legacy), 0)
        XCTAssertNil(current.object(forKey: "SUAutomaticallyUpdate"))
    }
}
