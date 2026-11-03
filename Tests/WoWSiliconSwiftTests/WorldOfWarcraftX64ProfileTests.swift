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

        // Existing third-party d3d9.dll is left byte for byte, whatever the graphics backend.
        let thirdParty = game.appendingPathComponent("d3d9.dll")
        try Data("third-party".utf8).write(to: thirdParty)
        for backend in GraphicsBackend.allCases {
            for driver in VulkanDriver.allCases {
                var other = version
                other.settings.graphicsSettings.backend = backend
                other.settings.graphicsSettings.vulkanDriver = driver
                try PatchService.installD3D9DLL(for: other)
                XCTAssertEqual(try Data(contentsOf: thirdParty), Data("third-party".utf8))
            }
        }
    }

    func testStatusCheckerFlagsStaleEmbeddedD3D9DLL() throws {
        let game = try makeTempDirectory()
        let version = try x64Version(gameDirectory: game)

        XCTAssertEqual(PatchingStatusChecker.evaluateGamePatch(for: version).text, "No patch needed")

        // A third-party d3d9.dll is not ours: still "No patch needed".
        let installed = game.appendingPathComponent("d3d9.dll")
        try Data("third-party".utf8).write(to: installed)
        XCTAssertEqual(PatchingStatusChecker.evaluateGamePatch(for: version).text, "No patch needed")

        for driver in VulkanDriver.allCases {
            let embedded = try XCTUnwrap(PatchService.resourceURL(
                named: "d3d9",
                extension: "dll",
                subdirectory: PatchService.d3d9ResourceSubdirectory(for: driver)
            ))
            try? FileManager.default.removeItem(at: installed)
            try FileManager.default.copyItem(at: embedded, to: installed)
            let status = PatchingStatusChecker.evaluateGamePatch(for: version)
            XCTAssertEqual(status.text, "Stale 32-bit d3d9.dll — click Unpatch to remove", "\(driver)")
            XCTAssertEqual(status.level, .warning)
            XCTAssertTrue(status.actionable)
            XCTAssertTrue(status.applied, "must not block launch")
        }

        try PatchService.removeGamePatch(for: version)
        XCTAssertEqual(PatchingStatusChecker.evaluateGamePatch(for: version).text, "No patch needed")
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

    // MARK: - Golden: 32-bit command strings unchanged vs main

    /// Verbatim copy of `makeShellCommand` from `main` (LaunchService.swift before #44), with its
    /// private helpers inlined. The 32-bit output of the current code must equal it exactly.
    private func mainReferenceCommand(
        gameURL: URL,
        x87Runtime: BundledX87Runtime.ResolvedRuntime?,
        wowURL: URL,
        wineExecutablePath: String,
        settings: VersionSettings
    ) -> String {
        let service = LaunchService.shared
        let game = service.shellQuote(gameURL.path)
        let wow = service.shellQuote(wowURL.path)
        let wine = service.shellQuote(wineExecutablePath)

        let mtlValue = settings.enableMetalHud ? "1" : "0"
        let spatialAudioMode = settings.spatializeStereo ? "fixed" : "off"
        let normalizeAudio = settings.normalizeAudio ? "1" : "0"
        let outputDeviceOverride = settings.audioOutputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_OUTPUT=0"
        let inputDeviceOverride = settings.audioInputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_INPUT=0"
        let dllOverride = settings.graphicsSettings.backend.wineDLLOverride
        let dyldLibraryPath = service.shellQuote(BundledWineRuntime.makeEnvironment()["DYLD_LIBRARY_PATH"] ?? "")
        let winePrefix = BundledWineRuntime.shellEnvironmentAssignment(
            key: "WINEPREFIX",
            value: WineRegistrySupport.winePrefixURL().path
        )
        var vulkanDriver = ""
        if settings.graphicsSettings.backend == .d9vk,
           let assignment = BundledWineRuntime.vulkanDriverShellAssignment(for: settings.graphicsSettings.vulkanDriver) {
            vulkanDriver = " \(assignment)"
        }
        let baseEnv = "\(winePrefix) DYLD_LIBRARY_PATH=\(dyldLibraryPath)\(vulkanDriver) WINE_LARGE_ADDRESS_AWARE=1 WINEDLLOVERRIDES=\(service.shellQuote(dllOverride))\(outputDeviceOverride)\(inputDeviceOverride) WOWSILICON_SPATIAL_AUDIO_MODE=\(spatialAudioMode) WOWSILICON_NORMALIZE_AUDIO=\(normalizeAudio) MTL_HUD_ENABLED=\(mtlValue) MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 DXVK_ASYNC=1"
        let custom = BundledWineRuntime.shellEnvironmentAssignments(settings.environmentVariables)
        let envPart = custom.isEmpty ? baseEnv : "\(custom) \(baseEnv)"

        if let x87Runtime {
            let binary = service.shellQuote(x87Runtime.executableURL.path)
            return "cd \(game) && \(x87Runtime.wineEnvironmentKey)=\(binary) \(envPart) \(wine) \(wow)"
        } else {
            return "cd \(game) && \(envPart) \(wine) \(wow)"
        }
    }

    func testMakeShellCommandIsIdenticalToMainFor32BitProfiles() throws {
        try withFakeWineRuntime { _ in
            let game = URL(fileURLWithPath: "/Games/It's WoW 3.3.5", isDirectory: true)
            let wow = game.appendingPathComponent("Wow.exe")
            let wine = "/Applications/SiloWow.app/Contents/Resources/Wine/bin/wine"
            let fakeX87 = BundledX87Runtime.ResolvedRuntime(
                executableURL: URL(fileURLWithPath: "/fake/Patching/rosettax87/rosettax87"),
                wineEnvironmentKey: "ROSETTA_X87_PATH"
            )
            let fakeSidecar = BundledX87Runtime.ResolvedRuntime(
                executableURL: URL(fileURLWithPath: "/fake/Patching/x87sidecar/x87sidecar"),
                wineEnvironmentKey: "X87_SIDECAR_PATH"
            )

            var cases: [(String, GameVersion, BundledX87Runtime.ResolvedRuntime?)] = []
            for runtime in [nil, fakeX87, fakeSidecar] as [BundledX87Runtime.ResolvedRuntime?] {
                cases.append(("wotlk", VersionManager.defaultVersions["wrathsilicon"]!, runtime))
                cases.append(("generic", VersionManager.genericD3D9Template, runtime))
            }

            var checked = 0
            for (label, base, runtime) in cases {
                XCTAssertTrue(base.profileKind == .worldOfWarcraft || base.profileKind == .genericD3D9, label)
                var variants: [VersionSettings] = []
                for backend in GraphicsBackend.allCases {
                    for driver in VulkanDriver.allCases {
                        var settings = base.settings
                        settings.graphicsSettings.backend = backend
                        settings.graphicsSettings.vulkanDriver = driver
                        variants.append(settings)
                    }
                }
                var custom = base.settings
                custom.environmentVariables = "B_VAR=2\nA_VAR='x y'"
                custom.enableMetalHud = true
                custom.spatializeStereo = true
                custom.normalizeAudio = true
                custom.audioOutputDeviceID = "out"
                custom.audioInputDeviceID = "in"
                variants.append(custom)

                for settings in variants {
                    let expected = mainReferenceCommand(
                        gameURL: game, x87Runtime: runtime, wowURL: wow, wineExecutablePath: wine, settings: settings
                    )
                    let actual = LaunchService.shared.makeShellCommand(
                        gameURL: game, x87Runtime: runtime, wowURL: wow, wineExecutablePath: wine,
                        settings: settings, profileKind: base.profileKind
                    )
                    XCTAssertEqual(actual, expected, label)
                    // Default profile kind (what main's signature implies) must also match.
                    if base.profileKind == .worldOfWarcraft {
                        XCTAssertEqual(
                            LaunchService.shared.makeShellCommand(
                                gameURL: game, x87Runtime: runtime, wowURL: wow, wineExecutablePath: wine, settings: settings
                            ),
                            expected
                        )
                    }
                    checked += 1
                }
            }
            XCTAssertEqual(checked, 3 * 2 * (GraphicsBackend.allCases.count * VulkanDriver.allCases.count + 1))
        }
    }

    func testPrepareLaunchOutputForGenericMatchesMainReference() throws {
        try withFakeWineRuntime { wineRoot in
            let game = try makeTempDirectory()
            let exe = game.appendingPathComponent("Wow.exe")
            XCTAssertTrue(FileManager.default.createFile(atPath: exe.path, contents: makePEData(machine: 0x014C)))
            let wine = wineRoot.appendingPathComponent("bin/wine").path
            let prefix = try makeTempDirectory()

            // Only the generic profile can be patched in a synthetic folder (WoW profiles need a real client);
            // the WoW profile is covered by the direct makeShellCommand golden test above.
            for var version in [VersionManager.genericD3D9Template] {
                version.gamePath = exe.path
                version.executableName = "Wow.exe"
                version.settings.x87Backend = .disabled
                try PatchService.applyGamePatch(for: version)

                let script = try LaunchService.shared.shortcutShellScript(for: version, winePrefixURL: prefix)
                let expected = mainReferenceCommand(
                    gameURL: game, x87Runtime: nil, wowURL: exe, wineExecutablePath: wine, settings: version.settings
                )
                XCTAssertTrue(script.contains(expected), "\(version.profileKind): command differs from main")
            }
        }
    }

    // MARK: - Architecture mismatch feedback

    @MainActor
    func testGamePathFeedbackFlagsX64ExecutableOn32BitProfile() throws {
        let dir = try makeTempDirectory()
        let exe = dir.appendingPathComponent("Wow-64.exe")
        XCTAssertTrue(FileManager.default.createFile(atPath: exe.path, contents: makePEData(machine: 0x8664)))
        let x86 = dir.appendingPathComponent("Wow.exe")
        XCTAssertTrue(FileManager.default.createFile(atPath: x86.path, contents: makePEData(machine: 0x014C)))

        for kind in [GameProfileKind.worldOfWarcraft, .genericD3D9] {
            let feedback = try XCTUnwrap(MainDashboardViewModel.architectureMismatchFeedback(for: exe, profileKind: kind))
            XCTAssertTrue(feedback.isError)
            XCTAssertTrue(feedback.message.contains("64-bit"))
            XCTAssertTrue(feedback.message.contains("Battle for Azeroth 8.3.7 (x64)"))
            XCTAssertNil(MainDashboardViewModel.architectureMismatchFeedback(for: x86, profileKind: kind))
        }
        XCTAssertNil(MainDashboardViewModel.architectureMismatchFeedback(for: exe, profileKind: .worldOfWarcraftX64))
        XCTAssertNotNil(MainDashboardViewModel.architectureMismatchFeedback(for: x86, profileKind: .worldOfWarcraftX64))
    }

    // MARK: - Vulkan driver error message

    func testVulkanDriverMissingMessageDependsOnDriver() {
        let molten = LaunchServiceError.vulkanDriverMissing(.moltenVK).errorDescription ?? ""
        XCTAssertTrue(molten.contains("MoltenVK"))
        XCTAssertTrue(molten.contains("tools/wine-runtime/restore.sh"))
        XCTAssertFalse(molten.contains("install-kosmickrisp.sh"))

        let kosmic = LaunchServiceError.vulkanDriverMissing(.kosmicKrisp).errorDescription ?? ""
        XCTAssertTrue(kosmic.contains(VulkanDriver.kosmicKrisp.displayName))
        XCTAssertTrue(kosmic.contains("tools/wine-runtime/install-kosmickrisp.sh"))
        XCTAssertFalse(kosmic.contains("restore.sh"))
    }

    func testX64LaunchReportsMissingMoltenVKDriver() throws {
        try withFakeWineRuntime { wineRoot in
            try FileManager.default.removeItem(
                at: wineRoot.appendingPathComponent("lib/vulkan/icd.d/\(VulkanDriver.moltenVK.manifestFileName)")
            )
            let game = try makeTempDirectory()
            let version = try x64Version(gameDirectory: game)
            XCTAssertThrowsError(try LaunchService.shared.shortcutShellScript(for: version, winePrefixURL: try makeTempDirectory())) { error in
                guard case LaunchServiceError.vulkanDriverMissing(.moltenVK) = error else {
                    return XCTFail("unexpected error \(error)")
                }
            }
        }
    }

    // MARK: - Wine prefix 64-bit capability

    private func makePrefix(system32: Bool, syswow64: Bool, driveC: Bool = true) throws -> URL {
        let prefix = try makeTempDirectory()
        if driveC {
            let windows = prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
            try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
            if system32 { try FileManager.default.createDirectory(at: windows.appendingPathComponent("system32"), withIntermediateDirectories: true) }
            if syswow64 { try FileManager.default.createDirectory(at: windows.appendingPathComponent("syswow64"), withIntermediateDirectories: true) }
        }
        return prefix
    }

    func testPrefixSupports64BitDetection() throws {
        XCTAssertTrue(LaunchService.prefixSupports64Bit(at: try makePrefix(system32: true, syswow64: true)))
        XCTAssertFalse(LaunchService.prefixSupports64Bit(at: try makePrefix(system32: true, syswow64: false)))
        XCTAssertFalse(LaunchService.prefixSupports64Bit(at: try makePrefix(system32: false, syswow64: true)))
        XCTAssertFalse(LaunchService.prefixSupports64Bit(at: try makePrefix(system32: false, syswow64: false)))
        // No drive_c yet: Wine will create a 64-bit prefix at first launch.
        XCTAssertTrue(LaunchService.prefixSupports64Bit(at: try makePrefix(system32: false, syswow64: false, driveC: false)))
        XCTAssertTrue(LaunchService.prefixSupports64Bit(at: URL(fileURLWithPath: "/nonexistent/prefix")))
    }

    func testPrefixCheckDoesNotCreateOrModifyAnything() throws {
        let prefix = try makePrefix(system32: true, syswow64: false)
        func listing() -> [String] {
            (FileManager.default.subpaths(atPath: prefix.path) ?? []).sorted()
        }
        let before = listing()
        _ = LaunchService.prefixSupports64Bit(at: prefix)
        XCTAssertEqual(listing(), before)
    }

    func testX64LaunchRefusesNon64BitPrefixOnly() throws {
        try withFakeWineRuntime { _ in
            let game = try makeTempDirectory()
            let version = try x64Version(gameDirectory: game)

            let bad = try makePrefix(system32: true, syswow64: false)
            XCTAssertThrowsError(try LaunchService.shared.shortcutShellScript(for: version, winePrefixURL: bad)) { error in
                guard case LaunchServiceError.winePrefixNot64BitCapable(let path) = error else {
                    return XCTFail("unexpected error \(error)")
                }
                XCTAssertEqual(path, bad.path)
                XCTAssertTrue(error.localizedDescription.contains("64-bit"))
            }

            let good = try makePrefix(system32: true, syswow64: true)
            XCTAssertNoThrow(try LaunchService.shared.shortcutShellScript(for: version, winePrefixURL: good))

            // 32-bit profiles are not subject to the check.
            let exe = game.appendingPathComponent("Game.exe")
            XCTAssertTrue(FileManager.default.createFile(atPath: exe.path, contents: makePEData(machine: 0x014C)))
            var generic = VersionManager.genericD3D9Template
            generic.gamePath = exe.path
            generic.executableName = "Game.exe"
            generic.settings.x87Backend = .disabled
            try PatchService.applyGamePatch(for: generic)
            XCTAssertNoThrow(try LaunchService.shared.shortcutShellScript(for: generic, winePrefixURL: bad))
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
