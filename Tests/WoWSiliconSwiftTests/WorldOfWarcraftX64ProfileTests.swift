import XCTest
@testable import WoWSiliconSwift

final class WorldOfWarcraftX64ProfileTests: XCTestCase {
    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSiliconX64Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Minimal PE image: MZ header, e_lfanew = 0x80, "PE\0\0", machine.
    private func makePEData(machine: UInt16, lfanew: UInt32 = 0x80) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0] = 0x4D
        bytes[1] = 0x5A
        for i in 0..<4 { bytes[0x3C + i] = UInt8((lfanew >> (8 * UInt32(i))) & 0xFF) }
        let offset = Int(lfanew)
        guard offset + 6 <= bytes.count else { return Data(bytes) }
        bytes[offset] = 0x50
        bytes[offset + 1] = 0x45
        bytes[offset + 4] = UInt8(machine & 0xFF)
        bytes[offset + 5] = UInt8(machine >> 8)
        return Data(bytes)
    }

    private func x64Version(gameDirectory: URL, executable: String = "WoW Circle.exe") throws -> GameVersion {
        let exe = gameDirectory.appendingPathComponent(executable)
        XCTAssertTrue(FileManager.default.createFile(atPath: exe.path, contents: makePEData(machine: 0x8664)))
        var version = VersionManager.bfa837X64Template
        version.id = "x64-test"
        version.gamePath = exe.path
        version.executableName = executable
        return version
    }

    // MARK: - Kind and template

    func testProfileKindRawValueAndRoundTrip() throws {
        XCTAssertEqual(GameProfileKind.worldOfWarcraftX64.rawValue, "world_of_warcraft_x64")
        let encoded = try JSONEncoder().encode(VersionManager.bfa837X64Template)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"world_of_warcraft_x64\""))
        let decoded = try JSONDecoder().decode(GameVersion.self, from: encoded)
        XCTAssertEqual(decoded, VersionManager.bfa837X64Template)
        XCTAssertEqual(decoded.profileKind, .worldOfWarcraftX64)
    }

    func testExistingKindsStillDecode() throws {
        let wow = try JSONDecoder().decode(
            GameVersion.self,
            from: Data(#"{"id":"a","display_name":"A","wow_version":"3.3.5a","profile_kind":"world_of_warcraft"}"#.utf8)
        )
        let generic = try JSONDecoder().decode(
            GameVersion.self,
            from: Data(#"{"id":"b","display_name":"B","wow_version":"","profile_kind":"generic_d3d9"}"#.utf8)
        )
        XCTAssertEqual(wow.profileKind, .worldOfWarcraft)
        XCTAssertEqual(generic.profileKind, .genericD3D9)
    }

    func testTemplateCapabilities() {
        let template = VersionManager.bfa837X64Template

        XCTAssertEqual(template.id, "bfa837x64")
        XCTAssertEqual(template.displayName, "Battle for Azeroth 8.3.7 (x64)")
        XCTAssertEqual(template.profileKind, .worldOfWarcraftX64)
        XCTAssertEqual(template.wowVersion, "8.3.7")
        XCTAssertEqual(template.executableName, "Wow.exe")
        XCTAssertFalse(template.supportsDLLLoading)
        XCTAssertFalse(template.usesRosettaPatching)
        XCTAssertFalse(template.supportsVanillaTweaks)
        XCTAssertEqual(template.settings.x87Backend, .disabled)
        XCTAssertFalse(template.settings.enableLibSiliconPatch)
        XCTAssertNil(template.libSiliconPatchSubdirectory)
        XCTAssertFalse(template.supportsRealmlist)
        XCTAssertFalse(template.supportsCustomGraphicsSettings)
        XCTAssertFalse(template.isWorldOfWarcraft)
        XCTAssertTrue(template.supportsAddons)
    }

    func testTemplateIsExposedAsTemplateButNotAsDefaultProfile() {
        XCTAssertNotNil(VersionManager.profileTemplates[VersionManager.bfa837X64TemplateID])
        XCTAssertNil(VersionManager.defaultVersions[VersionManager.bfa837X64TemplateID])
        var manager = VersionManager.makeDefault()
        manager.ensureDefaults()
        XCTAssertNil(manager.versions[VersionManager.bfa837X64TemplateID])
    }

    // MARK: - Patching

    func testApplyPatchCopiesNothingAndDoesNotRequireWoWClient() throws {
        let game = try makeTempDirectory()
        let version = try x64Version(gameDirectory: game)
        let thirdParty = game.appendingPathComponent("d3d9.dll")
        try Data("third-party".utf8).write(to: thirdParty)

        let before = try FileManager.default.contentsOfDirectory(atPath: game.path).sorted()
        XCTAssertNoThrow(try PatchService.applyGamePatch(for: version))
        let after = try FileManager.default.contentsOfDirectory(atPath: game.path).sorted()

        XCTAssertEqual(before, after)
        for name in ["mods", "mtld3d.conf", "libDllLdr.dll", "dlls.txt", "DivxDecoder.dll.bak"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: game.appendingPathComponent(name).path), name)
        }
        XCTAssertEqual(try Data(contentsOf: thirdParty), Data("third-party".utf8))
    }

    func testApplyPatchRemovesOnlyEmbeddedD3D9DLL() throws {
        for driver in VulkanDriver.allCases {
            let game = try makeTempDirectory()
            let version = try x64Version(gameDirectory: game)
            let embedded = try XCTUnwrap(PatchService.resourceURL(
                named: "d3d9",
                extension: "dll",
                subdirectory: PatchService.d3d9ResourceSubdirectory(for: driver)
            ))
            let installed = game.appendingPathComponent("d3d9.dll")

            try FileManager.default.copyItem(at: embedded, to: installed)
            try PatchService.applyGamePatch(for: version)
            XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path), "\(driver) d3d9 kept")

            try Data("third-party".utf8).write(to: installed)
            try PatchService.applyGamePatch(for: version)
            XCTAssertEqual(try Data(contentsOf: installed), Data("third-party".utf8))
        }
    }

    func testRemovePatchOnlyCleansEmbeddedD3D9DLL() throws {
        let game = try makeTempDirectory()
        let version = try x64Version(gameDirectory: game)
        let keepFiles = ["mtld3d.conf", "libDllLdr.dll", "DivxDecoder.dll"]
        for name in keepFiles {
            try Data("keep".utf8).write(to: game.appendingPathComponent(name))
        }
        let embedded = try XCTUnwrap(PatchService.resourceURL(
            named: "d3d9",
            extension: "dll",
            subdirectory: PatchService.d3d9ResourceSubdirectory(for: .moltenVK)
        ))
        let installed = game.appendingPathComponent("d3d9.dll")
        try FileManager.default.copyItem(at: embedded, to: installed)

        try PatchService.removeGamePatch(for: version)

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        for name in keepFiles {
            XCTAssertEqual(try Data(contentsOf: game.appendingPathComponent(name)), Data("keep".utf8), name)
        }

        try Data("third-party".utf8).write(to: installed)
        try PatchService.removeGamePatch(for: version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
    }

    func testInstallD3D9DLLIsNoOpForX64() throws {
        let game = try makeTempDirectory()
        let version = try x64Version(gameDirectory: game)
        try PatchService.installD3D9DLL(for: version)
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appendingPathComponent("d3d9.dll").path))
    }

    func testStatusCheckerConsidersX64Ready() throws {
        let game = try makeTempDirectory()
        var version = try x64Version(gameDirectory: game)

        XCTAssertTrue(PatchingStatusChecker.evaluateGamePatch(for: version).applied)

        try FileManager.default.removeItem(atPath: version.gamePath)
        let missing = PatchingStatusChecker.evaluateGamePatch(for: version)
        XCTAssertFalse(missing.applied)
        XCTAssertFalse(missing.actionable)

        version.gamePath = ""
        XCTAssertFalse(PatchingStatusChecker.evaluateGamePatch(for: version).applied)
    }

    // MARK: - Launch command

    private func withFakeWineRuntime(_ body: (URL) throws -> Void) throws {
        let root = try makeTempDirectory()
        let wineRoot = root.appendingPathComponent("Wine", isDirectory: true)
        let wineExecutable = wineRoot.appendingPathComponent("bin/wine", isDirectory: false)
        let icd = wineRoot.appendingPathComponent("lib/vulkan/icd.d", isDirectory: true)
        try FileManager.default.createDirectory(at: wineExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: icd, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: wineExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wineExecutable.path)
        try Data("{}".utf8).write(to: icd.appendingPathComponent(VulkanDriver.moltenVK.manifestFileName))
        try Data("{}".utf8).write(to: icd.appendingPathComponent(VulkanDriver.kosmicKrisp.manifestFileName))

        let key = BundledWineRuntime.environmentOverride
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, wineRoot.path, 1)
        defer {
            if let previous { setenv(key, previous, 1) } else { unsetenv(key) }
        }
        try body(wineRoot)
    }

    func testLaunchCommandUsesSpikeConfiguration() throws {
        try withFakeWineRuntime { wineRoot in
            let game = try makeTempDirectory()
            var version = try x64Version(gameDirectory: game)
            // Profile settings that must NOT leak into the x64 command.
            version.settings.graphicsSettings.vulkanDriver = .kosmicKrisp
            version.settings.x87Backend = .rosettaX87
            version.settings.environmentVariables = "MY_CUSTOM_VAR=42"

            let script = try LaunchService.shared.shortcutShellScript(for: version)

            let moltenManifest = wineRoot.appendingPathComponent("lib/vulkan/icd.d/MoltenVK_icd.json").path
            let expectedVK = try XCTUnwrap(BundledWineRuntime.vulkanDriverShellAssignment(for: .moltenVK))
            XCTAssertTrue(expectedVK.contains(moltenManifest))
            XCTAssertTrue(script.contains("WINE_D3D_CONFIG=renderer=vulkan"))
            XCTAssertTrue(script.contains(expectedVK))
            XCTAssertFalse(script.contains("KosmicKrisp_icd.json"))
            XCTAssertTrue(script.contains("WINEPREFIX="))
            XCTAssertTrue(script.contains("DYLD_LIBRARY_PATH="))
            XCTAssertTrue(script.contains("MY_CUSTOM_VAR"))
            XCTAssertFalse(script.contains("WINEDLLOVERRIDES"))
            XCTAssertFalse(script.contains("WINE_LARGE_ADDRESS_AWARE"))
            XCTAssertFalse(script.contains("DXVK_ASYNC"))
            XCTAssertFalse(script.lowercased().contains("x87"))
            XCTAssertFalse(script.contains("WINE_ROSETTAX87"))
            XCTAssertTrue(script.contains("WoW Circle.exe' -d3d11"))
        }
    }

    func testLaunchCommandDoesNotChangeFor32BitProfiles() throws {
        try withFakeWineRuntime { _ in
            let game = try makeTempDirectory()
            let exe = game.appendingPathComponent("Game.exe")
            XCTAssertTrue(FileManager.default.createFile(atPath: exe.path, contents: makePEData(machine: 0x014C)))
            var version = VersionManager.genericD3D9Template
            version.gamePath = exe.path
            version.executableName = "Game.exe"
            version.settings.x87Backend = .disabled
            try PatchService.applyGamePatch(for: version)

            let script = try LaunchService.shared.shortcutShellScript(for: version)

            XCTAssertTrue(script.contains("WINEDLLOVERRIDES"))
            XCTAssertTrue(script.contains("WINE_LARGE_ADDRESS_AWARE=1"))
            XCTAssertTrue(script.contains("DXVK_ASYNC=1"))
            XCTAssertFalse(script.contains("-d3d11"))
            XCTAssertFalse(script.contains("WINE_D3D_CONFIG"))
        }
    }

    // MARK: - PEArchitecture

    func testPEArchitectureParsesMachineTypes() {
        XCTAssertEqual(PEArchitecture.parse(makePEData(machine: 0x014C)), .x86)
        XCTAssertEqual(PEArchitecture.parse(makePEData(machine: 0x8664)), .x86_64)
        XCTAssertEqual(PEArchitecture.parse(makePEData(machine: 0xAA64)), .unknown)
    }

    func testPEArchitectureReadsFilesAndSurvivesBadInput() throws {
        let dir = try makeTempDirectory()
        func write(_ name: String, _ data: Data) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }

        XCTAssertEqual(PEArchitecture.read(from: try write("x86.exe", makePEData(machine: 0x014C))), .x86)
        XCTAssertEqual(PEArchitecture.read(from: try write("x64.exe", makePEData(machine: 0x8664))), .x86_64)
        // Truncated: header cut before the machine field, and cut before e_lfanew.
        XCTAssertEqual(PEArchitecture.read(from: try write("trunc1.exe", makePEData(machine: 0x8664).prefix(0x84))), .unknown)
        XCTAssertEqual(PEArchitecture.read(from: try write("trunc2.exe", makePEData(machine: 0x8664).prefix(0x20))), .unknown)
        XCTAssertEqual(PEArchitecture.read(from: try write("empty.exe", Data())), .unknown)
        // Not an MZ file, bad PE signature, e_lfanew pointing past the end.
        XCTAssertEqual(PEArchitecture.read(from: try write("text.exe", Data(repeating: 0x41, count: 0x200))), .unknown)
        var badSignature = makePEData(machine: 0x8664)
        badSignature[0x80] = 0x00
        XCTAssertEqual(PEArchitecture.read(from: try write("badsig.exe", badSignature)), .unknown)
        XCTAssertEqual(PEArchitecture.parse(makePEData(machine: 0x8664, lfanew: 0xFFFF_FFF0)), .unknown)
        XCTAssertEqual(PEArchitecture.read(from: dir.appendingPathComponent("missing.exe")), .unknown)
    }

    func testMismatchMessageProposesTheRightTemplate() {
        for kind in [GameProfileKind.worldOfWarcraft, .genericD3D9] {
            let message = PEArchitecture.mismatchMessage(for: .x86_64, profileKind: kind)
            XCTAssertNotNil(message)
            XCTAssertTrue(message?.contains("Battle for Azeroth 8.3.7 (x64)") == true)
            XCTAssertNil(PEArchitecture.mismatchMessage(for: .x86, profileKind: kind))
            XCTAssertNil(PEArchitecture.mismatchMessage(for: .unknown, profileKind: kind))
        }
        XCTAssertNotNil(PEArchitecture.mismatchMessage(for: .x86, profileKind: .worldOfWarcraftX64))
        XCTAssertNil(PEArchitecture.mismatchMessage(for: .x86_64, profileKind: .worldOfWarcraftX64))
        XCTAssertNil(PEArchitecture.mismatchMessage(for: .unknown, profileKind: .worldOfWarcraftX64))
    }
}
