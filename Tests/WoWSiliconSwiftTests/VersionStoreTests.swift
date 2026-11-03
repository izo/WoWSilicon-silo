import XCTest
@testable import WoWSiliconSwift

final class VersionStoreTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        try super.tearDownWithError()
    }

    func testSaveAndLoadRoundTripsCustomProfileAndDefaults() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)
        let custom = GameVersion(
            id: "custom",
            displayName: "Custom",
            wowVersion: "1.12.1",
            gamePath: "/Games/WoW",
            executableName: "WoW.exe",
            supportsVanillaTweaks: true,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            settings: VersionSettings(enableMetalHud: true)
        )
        var manager = VersionManager.makeDefault()
        manager.currentVersionID = "custom"
        manager.versions["custom"] = custom

        try store.save(manager: manager)
        let result = store.loadVersionManager()

        XCTAssertFalse(result.decodeFailed)
        XCTAssertEqual(result.manager.currentVersionID, "custom")
        XCTAssertEqual(result.manager.versions["custom"]?.gamePath, "/Games/WoW")
        XCTAssertEqual(result.manager.versions["custom"]?.settings.enableMetalHud, true)
        XCTAssertNotNil(result.manager.versions["vanillasilicon"])
        XCTAssertNotNil(result.manager.versions["burningsilicon"])
        XCTAssertNotNil(result.manager.versions["wrathsilicon"])
    }

    func testLoadFallsBackToDefaultsWhenVersionsFileIsInvalid() throws {
        let supportURL = try makeTemporaryDirectory()
        let versionsURL = supportURL.appendingPathComponent("SiloWow/versions.json")
        try FileManager.default.createDirectory(at: versionsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{ not json".write(to: versionsURL, atomically: true, encoding: .utf8)

        let result = VersionStore(supportDirectory: supportURL).loadVersionManager()

        XCTAssertTrue(result.decodeFailed)
        XCTAssertEqual(result.manager.currentVersionID, VersionManager.defaultCurrentVersionID)
        XCTAssertEqual(Set(result.manager.versions.keys), Set(VersionManager.defaultVersions.keys))
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testLoadMergesLegacyVersionManagerWhenNewStoreHasNoPaths() throws {
        let supportURL = try makeTemporaryDirectory()
        let legacyURL = supportURL.appendingPathComponent("SiloWow/version_manager.json")
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "current_version_id": "wrathsilicon",
          "versions": {
            "wrathsilicon": {
              "game_path": "/Games/Wrath",
              "settings": {
                "environment_variables": "FOO=BAR",
                "auto_delete_wdb": false,
                "enable_metal_hud": true,
                "show_terminal_normally": true,
                "enable_lib_silicon_patch": true
              }
            }
          }
        }
        """.write(to: legacyURL, atomically: true, encoding: .utf8)

        let result = VersionStore(supportDirectory: supportURL).loadVersionManager()
        let wrath = try XCTUnwrap(result.manager.versions["wrathsilicon"])

        XCTAssertEqual(result.manager.currentVersionID, "wrathsilicon")
        XCTAssertEqual(wrath.gamePath, "/Games/Wrath")
        XCTAssertEqual(wrath.settings.environmentVariables, "FOO=BAR")
        XCTAssertFalse(wrath.settings.autoDeleteWdb)
        XCTAssertTrue(wrath.settings.enableMetalHud)
        XCTAssertTrue(wrath.settings.showTerminalNormally)
    }

    func testProfileSelectionPreservesDistinctSettingsAcrossSaveAndLoad() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)
        let firstSettings = VersionSettings(
            enableVanillaTweaks: true,
            autoDeleteWdb: true,
            enableMetalHud: true,
            showTerminalNormally: true,
            environmentVariables: "PROFILE=FIRST",
            vanillaTweaksParameters: "--first",
            graphicsSettings: GraphicsSettings(backend: .mtld3d, resolution: "1920x1080"),
            x87Backend: .x87Sidecar
        )
        let secondSettings = VersionSettings(
            enableVanillaTweaks: false,
            autoDeleteWdb: false,
            enableMetalHud: false,
            showTerminalNormally: false,
            environmentVariables: "PROFILE=SECOND",
            vanillaTweaksParameters: "--second",
            graphicsSettings: GraphicsSettings(backend: .d9vk, resolution: "2560x1440"),
            x87Backend: .disabled
        )
        var manager = VersionManager(
            currentVersionID: "first",
            versions: [
                "first": GameVersion(
                    id: "first",
                    displayName: "First",
                    wowVersion: "1.12.1",
                    executableName: "WoW.exe",
                    supportsVanillaTweaks: true,
                    supportsDLLLoading: true,
                    usesRosettaPatching: true,
                    settings: firstSettings
                ),
                "second": GameVersion(
                    id: "second",
                    displayName: "Second",
                    wowVersion: "1.12.1",
                    executableName: "WoW.exe",
                    supportsVanillaTweaks: true,
                    supportsDLLLoading: true,
                    usesRosettaPatching: true,
                    settings: secondSettings
                )
            ]
        )

        manager.setCurrentVersion(id: "second")
        manager.setCurrentVersion(id: "first")
        manager.setCurrentVersion(id: "second")

        XCTAssertEqual(manager.versions["first"]?.settings, firstSettings)
        XCTAssertEqual(manager.versions["second"]?.settings, secondSettings)

        try store.save(manager: manager)
        let reloaded = store.loadVersionManager()

        XCTAssertFalse(reloaded.requiresLegacyPrefsMigration)
        XCTAssertEqual(reloaded.manager.currentVersionID, "second")
        XCTAssertEqual(reloaded.manager.versions["first"]?.settings, firstSettings)
        XCTAssertEqual(reloaded.manager.versions["second"]?.settings, secondSettings)
    }

    func testMissingVersionStoreRequestsLegacyPreferencesMigrationOnlyOnce() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)

        let initial = store.loadVersionManager()
        XCTAssertTrue(initial.requiresLegacyPrefsMigration)

        try store.save(manager: initial.manager)
        let reloaded = store.loadVersionManager()
        XCTAssertFalse(reloaded.requiresLegacyPrefsMigration)
    }

    func testSavingUnchangedManagerDoesNotRewriteFile() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)
        let manager = VersionManager.makeDefault()
        let versionsURL = supportURL.appendingPathComponent("SiloWow/versions.json")

        try store.save(manager: manager)
        let originalModificationDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate],
            ofItemAtPath: versionsURL.path
        )

        try store.save(manager: manager)

        let attributes = try FileManager.default.attributesOfItem(atPath: versionsURL.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, originalModificationDate)
    }

    func testCorruptVersionsFileIsKeptAsBackupAndNeverOverwritten() throws {
        let supportURL = try makeTemporaryDirectory()
        let dir = supportURL.appendingPathComponent("SiloWow")
        let versionsURL = dir.appendingPathComponent("versions.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let corrupt = "{ not json, my precious profiles"
        try corrupt.write(to: versionsURL, atomically: true, encoding: .utf8)

        let store = VersionStore(supportDirectory: supportURL)
        let result = store.loadVersionManager()

        XCTAssertTrue(result.decodeFailed)
        XCTAssertFalse(result.persistenceBlocked)
        let backup = try XCTUnwrap(result.corruptBackupURL)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("versions.json.corrupt-"))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), corrupt)

        // A later save writes the new file but leaves the backup untouched.
        try store.save(manager: result.manager)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), corrupt)
        XCTAssertFalse(try String(contentsOf: versionsURL, encoding: .utf8).contains("precious"))
    }

    func testTwoCorruptionsInTheSameSecondKeepBothBackups() throws {
        let dir = try makeTemporaryDirectory().appendingPathComponent("SiloWow")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("versions.json")
        let now = Date()
        try "one".write(to: url, atomically: true, encoding: .utf8)
        let first = CorruptFileBackup.preserve(url, now: now)
        try "two".write(to: url, atomically: true, encoding: .utf8)
        let second = CorruptFileBackup.preserve(url, now: now)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(first), encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(second), encoding: .utf8), "two")
    }

    func testUnknownProfileKindIsPreservedAndDoesNotBreakOtherProfiles() throws {
        let supportURL = try makeTemporaryDirectory()
        let store = VersionStore(supportDirectory: supportURL)
        var manager = VersionManager.makeDefault()
        var future = try XCTUnwrap(VersionManager.defaultVersions["wrathsilicon"])
        future.id = "future"
        future.displayName = "Future"
        future.gamePath = "/Games/Future"
        future.profileKind = .unknown("quantum_client")
        var known = future
        known.id = "known"
        known.displayName = "Known"
        known.gamePath = "/Games/Known"
        known.profileKind = .genericD3D9
        manager.versions["future"] = future
        manager.versions["known"] = known
        try store.save(manager: manager)

        let raw = try String(contentsOf: supportURL.appendingPathComponent("SiloWow/versions.json"), encoding: .utf8)
        XCTAssertTrue(raw.contains("\"quantum_client\""))

        let result = store.loadVersionManager()
        XCTAssertFalse(result.decodeFailed)
        XCTAssertNil(result.corruptBackupURL)
        XCTAssertEqual(result.manager.versions["known"]?.profileKind, .genericD3D9)
        XCTAssertEqual(result.manager.versions["known"]?.gamePath, "/Games/Known")
        XCTAssertEqual(result.manager.versions["future"]?.profileKind, .unknown("quantum_client"))
        XCTAssertEqual(result.manager.versions["future"]?.gamePath, "/Games/Future")

        // Round trip once more: still written unchanged.
        try store.save(manager: result.manager)
        let again = try String(contentsOf: supportURL.appendingPathComponent("SiloWow/versions.json"), encoding: .utf8)
        XCTAssertEqual(raw, again)
    }

    func testKnownProfileKindsDecodeAsBefore() throws {
        for kind in [GameProfileKind.worldOfWarcraft, .genericD3D9, .worldOfWarcraftX64] {
            let data = try JSONEncoder().encode([kind])
            XCTAssertEqual(try JSONDecoder().decode([GameProfileKind].self, from: data), [kind])
            XCTAssertFalse(kind.isUnknown)
        }
        XCTAssertEqual(GameProfileKind(rawValue: "world_of_warcraft_x64"), .worldOfWarcraftX64)
    }

    func testUnknownProfileKindCannotBeLaunched() async throws {
        var version = try XCTUnwrap(VersionManager.defaultVersions["wrathsilicon"])
        version.gamePath = "/Games/Whatever"
        version.profileKind = .unknown("quantum_client")
        do {
            try await LaunchService.shared.launch(version: version)
            XCTFail("expected failure")
        } catch let error as LaunchServiceError {
            guard case .unsupportedProfileKind("quantum_client") = error else {
                return XCTFail("wrong error \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("cannot be launched"))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconSwiftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempURLs.append(url)
        return url
    }
}
