import Foundation
import AppKit

struct WineApplicationFocusMatcher {
    let baselineProcessIDs: Set<pid_t>
    let runtimeRootURL: URL
    let additionalExecutableURLs: Set<URL>
    private(set) var didMatch = false

    init(
        baselineProcessIDs: Set<pid_t>,
        runtimeRootURL: URL,
        additionalExecutableURLs: Set<URL> = []
    ) {
        self.baselineProcessIDs = baselineProcessIDs
        self.runtimeRootURL = runtimeRootURL
        self.additionalExecutableURLs = additionalExecutableURLs
    }

    mutating func accepts(processIdentifier: pid_t, executableURL: URL?) -> Bool {
        guard !didMatch,
              !baselineProcessIDs.contains(processIdentifier),
              let executableURL else {
            return false
        }

        let runtimePath = runtimeRootURL.standardizedFileURL.path
        let executablePath = executableURL.standardizedFileURL.path
        let additionalExecutablePaths = Set(additionalExecutableURLs.map { $0.standardizedFileURL.path })
        guard executablePath == runtimePath
                || executablePath.hasPrefix(runtimePath + "/")
                || additionalExecutablePaths.contains(executablePath) else {
            return false
        }

        didMatch = true
        return true
    }
}

enum LaunchServiceError: LocalizedError {
    case alreadyRunning
    case gamePathMissing
    case x87RuntimeMissing(String)
    case vulkanDriverUnsupported(String)
    case vulkanDriverMissing(VulkanDriver)
    case winePrefixNot64BitCapable(String)
    case wineMissing(String)
    case executableMissing(String)
    case vanillaTweaksMissing
    case patchNotApplied
    case wdbCleanupFailed(String)
    case processLaunchFailed(String)
    case appleScriptFailed(String)
    case versionMismatch(String, String)
    case unsupportedProfileKind(String)
    case wineProcessFailed(WineLaunchFailure, logPath: String?)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "The game is already running."
        case .gamePathMissing:
            return "Game path is not set. Please configure it before launching."
        case .x87RuntimeMissing(let path):
            return "Selected x87 runtime not found at \(path). Reinstall SiloWow and try again."
        case .vulkanDriverUnsupported(let driver):
            return "\(driver) requires macOS 26 or later. Select MoltenVK in Graphics settings."
        case .vulkanDriverMissing(let driver):
            switch driver {
            case .moltenVK:
                return "The MoltenVK Vulkan driver is missing from the bundled Wine runtime, so the runtime is incomplete. Restore it with tools/wine-runtime/restore.sh --runtime .wine-runtime and rebuild SiloWow."
            case .kosmicKrisp:
                return "The \(driver.displayName) Vulkan driver is not installed in this Wine runtime. Run tools/wine-runtime/install-kosmickrisp.sh and rebuild SiloWow."
            }
        case .winePrefixNot64BitCapable(let path):
            return "The Wine prefix at \(path) cannot run 64-bit programs (system32 and syswow64 are not both present). It looks like a 32-bit prefix. Choose another Wine bottle in Options or recreate this one with the bundled Wine runtime, then try again."
        case .wineMissing(let path):
            return "Bundled Wine executable not found at \(path). Reinstall SiloWow and try again."
        case .executableMissing(let path):
            return "Game executable not found at \(path). Please verify your game installation."
        case .vanillaTweaksMissing:
            return "Vanilla Tweaks is enabled but WoW_tweaked.exe was not found. SiloWow can create it automatically before launching."
        case .patchNotApplied:
            return "Patches no longer appear to be applied. Re-run the patching steps before launching."
        case .wdbCleanupFailed(let reason):
            return "Could not clear the WDB cache before launch. \(reason)"
        case .processLaunchFailed(let reason):
            return reason
        case .appleScriptFailed(let reason):
            return "Failed to launch in Terminal: \(reason)"
        case .unsupportedProfileKind(let kind):
            return "This profile uses the type \"\(kind)\", which this version of SiloWow does not know. The profile is kept as is, but it cannot be launched. Update SiloWow to use it."
        case .wineProcessFailed(let failure, let logPath):
            return failure.userMessage(logPath: logPath)
        case .versionMismatch(let base, let tweaked):
            return "Build mismatch detected.\n\nWoW.exe: \(base)\nWoW_tweaked.exe: \(tweaked)\n\nWoWSilicon can re-generate the tweaked executable for you."
        }
    }
}

final class LaunchService: @unchecked Sendable {
    static let shared = LaunchService()

    var processDidTerminate: (() -> Void)?
    /// Called on the main queue when an integrated launch dies with a known or startup failure.
    var processDidFail: ((LaunchServiceError) -> Void)?

    private var runningProcesses: [Process] = []
    private let processQueue = DispatchQueue(label: "com.turtlesilicon.launchservice.processes")
    private let fileManager = FileManager.default
    private var focusObservation: FocusObservation?

    private struct FocusObservation {
        let id: UUID
        var matcher: WineApplicationFocusMatcher
        let observer: NSObjectProtocol
        let timeout: DispatchWorkItem
    }

    private init() {}

    func launch(version: GameVersion) async throws {
        try Task.checkCancellation()
        let preparation = Task.detached(priority: .userInitiated) { [self] in
            try Task.checkCancellation()
            if version.settings.enableVanillaTweaks,
               let mismatch = checkVersionMismatch(for: version) {
                throw LaunchServiceError.versionMismatch(mismatch.base, mismatch.tweaked)
            }

            do {
                try LaunchPerformance.measure("Audio Device Setup") {
                    try AudioOutputService.applySavedDevices(
                        outputID: version.settings.audioOutputDeviceID,
                        inputID: version.settings.audioInputDeviceID,
                        customVariables: version.settings.environmentVariables
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                debugPrint("Could not apply the saved Wine audio output: \(error.localizedDescription)")
            }

            try Task.checkCancellation()
            let result = try LaunchPerformance.measure("Launch Artifact Preparation") {
                try prepareLaunchArtifacts(for: version)
            }

            try Task.checkCancellation()
            let patchesAreValid = LaunchPerformance.measure("Patch Validation") {
                patchesAppearValid(for: version)
            }
            if !patchesAreValid {
                throw LaunchServiceError.patchNotApplied
            }
            try Task.checkCancellation()
            return result
        }
        let result = try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: {
            preparation.cancel()
        }

        try Task.checkCancellation()
        try await MainActor.run {
            try Task.checkCancellation()
            if version.settings.showTerminalNormally {
                try LaunchPerformance.measure("Wine Process Spawn") {
                    try launchViaTerminal(configuration: result)
                }
                DispatchQueue.main.async { self.processDidTerminate?() }
            } else {
                try LaunchPerformance.measure("Wine Process Spawn") {
                    try launchIntegrated(configuration: result)
                }
            }
        }
    }

    // MARK: - Preparation

    private struct LaunchConfiguration: Sendable {
        let version: GameVersion
        let gameURL: URL
        let wowExecutableURL: URL
        let x87Runtime: BundledX87Runtime.ResolvedRuntime?
        let shellCommand: String
        let wineExecutablePath: String
    }

    private func prepareLaunchArtifacts(
        for version: GameVersion,
        performPrelaunchActions: Bool = true,
        winePrefixURL: URL = WineRegistrySupport.winePrefixURL()
    ) throws -> LaunchConfiguration {
        if case .unknown(let kind) = version.profileKind {
            throw LaunchServiceError.unsupportedProfileKind(kind)
        }
        let trimmedGame = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGame.isEmpty, let gameURL = version.gameDirectoryURL else { throw LaunchServiceError.gamePathMissing }

        let isX64 = version.isWorldOfWarcraftX64
        // x64 clients never use x87 translation, whatever the profile settings say.
        let x87Backend: X87Backend = isX64 ? .disabled : version.settings.x87Backend
        let x87Runtime = BundledX87Runtime.resolve(x87Backend)
        if x87Backend != .disabled && x87Runtime == nil {
            throw LaunchServiceError.x87RuntimeMissing(
                BundledX87Runtime.expectedBundlePath(for: version.settings.x87Backend)
            )
        }

        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            throw LaunchServiceError.wineMissing(expectedPath)
        }

        if isX64 {
            // The x64 pipeline always runs on MoltenVK (KosmicKrisp closes the client).
            guard BundledWineRuntime.vulkanDriverManifestURL(for: .moltenVK) != nil else {
                throw LaunchServiceError.vulkanDriverMissing(.moltenVK)
            }
            guard Self.prefixSupports64Bit(at: winePrefixURL, fileManager: fileManager) else {
                throw LaunchServiceError.winePrefixNot64BitCapable(winePrefixURL.path)
            }
        } else if version.settings.graphicsSettings.backend == .d9vk {
            let driver = version.settings.graphicsSettings.vulkanDriver
            guard driver.isSupportedOnCurrentMacOS else {
                throw LaunchServiceError.vulkanDriverUnsupported(driver.displayName)
            }
            if driver == .kosmicKrisp,
               BundledWineRuntime.vulkanDriverManifestURL(for: driver) == nil {
                throw LaunchServiceError.vulkanDriverMissing(driver)
            }
        }

        let wowExecutableURL: URL
        if version.settings.enableVanillaTweaks {
            let tweakedURL = gameURL.appendingPathComponent("WoW_tweaked.exe")
            if fileManager.fileExists(atPath: tweakedURL.path) {
                wowExecutableURL = tweakedURL
            } else {
                throw LaunchServiceError.vanillaTweaksMissing
            }
        } else if let exeURL = version.gameExecutableURL, fileManager.fileExists(atPath: exeURL.path) {
            wowExecutableURL = exeURL
        } else {
            let wowExe = gameURL.appendingPathComponent("WoW.exe")
            let ascensionExe = gameURL.appendingPathComponent("Ascension.exe")
            if fileManager.fileExists(atPath: wowExe.path) {
                wowExecutableURL = wowExe
            } else if fileManager.fileExists(atPath: ascensionExe.path) {
                wowExecutableURL = ascensionExe
            } else {
                wowExecutableURL = version.gameExecutableURL ?? wowExe
            }
        }

        guard fileManager.fileExists(atPath: wowExecutableURL.path) else {
            throw LaunchServiceError.executableMissing(wowExecutableURL.path)
        }

        try Task.checkCancellation()
        if performPrelaunchActions {
            _ = try LaunchPerformance.measure("WDB Cleanup") {
                try Self.cleanWDBIfEnabled(
                    version.settings.autoDeleteWdb,
                    at: gameURL,
                    fileManager: fileManager
                )
            }
        }

        if performPrelaunchActions, isX64 {
            try ClientConfigWTFService.apply(settings: version.settings, gameURL: gameURL, fileManager: fileManager)
        }

        try Task.checkCancellation()
        let spatialAudioControlURL = SpatialAudioService.controlURL()
        let normalizeAudioControlURL = SpatialAudioService.normalizeAudioControlURL()
        if performPrelaunchActions {
            try LaunchPerformance.measure("Audio Control Writes") {
                try SpatialAudioService.setEnabled(version.settings.spatializeStereo, controlURL: spatialAudioControlURL)
                try SpatialAudioService.setNormalizeAudio(version.settings.normalizeAudio, controlURL: normalizeAudioControlURL)
            }
        }

        let shellCommand = makeShellCommand(
            gameURL: gameURL,
            x87Runtime: x87Runtime,
            wowURL: wowExecutableURL,
            wineExecutablePath: wineExecutableURL.path,
            settings: version.settings,
            profileKind: version.profileKind
        )

        return LaunchConfiguration(
            version: version,
            gameURL: gameURL,
            wowExecutableURL: wowExecutableURL,
            x87Runtime: x87Runtime,
            shellCommand: shellCommand,
            wineExecutablePath: wineExecutableURL.path
        )
    }

    /// A prefix runs 64-bit programs when Wine created it in WoW64 mode: both `system32`
    /// (64-bit DLLs) and `syswow64` (32-bit DLLs) exist. A prefix that does not exist yet is
    /// accepted, because Wine creates a 64-bit one at first launch. Read-only: never creates
    /// or modifies a prefix.
    static func prefixSupports64Bit(at prefixURL: URL, fileManager: FileManager = .default) -> Bool {
        let windows = prefixURL.appendingPathComponent("drive_c/windows", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: prefixURL.appendingPathComponent("drive_c").path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return true }
        return ["system32", "syswow64"].allSatisfy { name in
            var isDir: ObjCBool = false
            return fileManager.fileExists(
                atPath: windows.appendingPathComponent(name, isDirectory: true).path,
                isDirectory: &isDir
            ) && isDir.boolValue
        }
    }

    func shortcutShellScript(
        for version: GameVersion,
        winePrefixURL: URL = WineRegistrySupport.winePrefixURL()
    ) throws -> String {
        let configuration = try prepareLaunchArtifacts(
            for: version,
            performPrelaunchActions: false,
            winePrefixURL: winePrefixURL
        )

        guard patchesAppearValid(for: version) else {
            throw LaunchServiceError.patchNotApplied
        }

        let spatialControlURL = SpatialAudioService.controlURL()
        let normalizeControlURL = SpatialAudioService.normalizeAudioControlURL()
        let supportDirectory = spatialControlURL.deletingLastPathComponent()
        let spatialMode = version.settings.spatializeStereo ? "fixed" : "off"
        let normalizeMode = version.settings.normalizeAudio ? "on" : "off"
        var setupCommands = [
            "/bin/mkdir -p \(shellQuote(supportDirectory.path))",
            "/usr/bin/printf '%s\\n' \(shellQuote(spatialMode)) > \(shellQuote(spatialControlURL.path))",
            "/usr/bin/printf '%s\\n' \(shellQuote(normalizeMode)) > \(shellQuote(normalizeControlURL.path))"
        ]
        setupCommands.append(contentsOf: try AudioOutputService.shortcutSelectionCommands(
            outputID: version.settings.audioOutputDeviceID,
            inputID: version.settings.audioInputDeviceID,
            customVariables: version.settings.environmentVariables
        ))

        if version.settings.autoDeleteWdb {
            let wdbURLs = [
                configuration.gameURL.appendingPathComponent("WDB", isDirectory: true),
                configuration.gameURL.appendingPathComponent("Cache/WDB", isDirectory: true)
            ]
            setupCommands.append(
                contentsOf: wdbURLs.map { url in
                    let failure = shellQuote("Could not clear the WDB cache at \(url.path)")
                    return "/bin/rm -rf \(shellQuote(url.path)) || { /usr/bin/printf '%s\\n' \(failure) >&2; exit 1; }"
                }
            )
        }

        let logName = shortcutSafeName(version.displayName) + ".log"
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WoWSilicon-\(logName)", isDirectory: false)
        return """
        # Generated by SiloWow for “\(version.displayName)”.
        \(setupCommands.joined(separator: "\n"))
        (
          \(configuration.shellCommand)
        ) >> \(shellQuote(logURL.path)) 2>&1 &
        """
    }

    // MARK: - Launch paths

    @MainActor
    private func launchIntegrated(configuration: LaunchConfiguration) throws {
        let focusID = startWineApplicationFocusObservation(
            additionalExecutableURL: configuration.x87Runtime?.executableURL
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", configuration.shellCommand]
        process.environment = BundledWineRuntime.makeEnvironment(
            customVariables: configuration.version.settings.environmentVariables
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let capture = WineOutputCapture(logURL: WineOutputCapture.defaultLogURL(profileID: configuration.version.id))
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            capture.append(data, stream: "stdout")
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                print("[GAME]", text)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            capture.append(data, stream: "stderr")
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                print("[GAME:ERR]", text)
            }
        }

        let startedAt = Date()
        process.terminationHandler = { [weak self] finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            // Drain what the handlers had not read yet before classifying.
            if let rest = try? stdout.fileHandleForReading.readToEnd() { capture.append(rest, stream: "stdout") }
            if let rest = try? stderr.fileHandleForReading.readToEnd() { capture.append(rest, stream: "stderr") }
            capture.close()
            let failure: LaunchServiceError? = finished.terminationReason == .exit
                ? WineOutputClassifier.classify(
                    exitCode: finished.terminationStatus,
                    duration: Date().timeIntervalSince(startedAt),
                    outputTail: capture.tailText
                ).map { .wineProcessFailed($0, logPath: capture.logURL?.path) }
                : nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.cancelWineApplicationFocusObservation(id: focusID)
                self.untrackProcess(process)
                if let failure { self.processDidFail?(failure) }
                self.processDidTerminate?()
            }
        }

        do {
            try Task.checkCancellation()
            try process.run()
            trackProcess(process)
        } catch {
            cancelWineApplicationFocusObservation(id: focusID)
            if error is CancellationError {
                throw error
            }
            throw LaunchServiceError.processLaunchFailed(error.localizedDescription)
        }
    }

    @MainActor
    private func launchViaTerminal(configuration: LaunchConfiguration) throws {
        try Task.checkCancellation()
        let focusID = startWineApplicationFocusObservation(
            additionalExecutableURL: configuration.x87Runtime?.executableURL
        )
        do {
            try launchTerminalCommand(configuration.shellCommand)
        } catch {
            cancelWineApplicationFocusObservation(id: focusID)
            throw error
        }
    }

    private func launchTerminalCommand(_ shellCommand: String) throws {
        let commandURL = fileManager.temporaryDirectory
            .appendingPathComponent("WoWSilicon-Launch-\(UUID().uuidString).sh", isDirectory: false)
        do {
            try (shellCommand + "\n").write(to: commandURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: commandURL.path)
        } catch {
            throw LaunchServiceError.appleScriptFailed(error.localizedDescription)
        }

        var terminalOwnsCommandFile = false
        defer {
            if !terminalOwnsCommandFile {
                try? fileManager.removeItem(at: commandURL)
            }
        }

        let bootstrapCommand = terminalBootstrapCommand(scriptURL: commandURL)
        let escaped = bootstrapCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application \"Terminal\"
            do script \"\(escaped)\"
            activate
        end tell
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                throw LaunchServiceError.appleScriptFailed("osascript exited with code \(task.terminationStatus)")
            }
            terminalOwnsCommandFile = true
        } catch let error as LaunchServiceError {
            throw error
        } catch {
            throw LaunchServiceError.appleScriptFailed(error.localizedDescription)
        }
    }

    func terminalBootstrapCommand(scriptURL: URL) -> String {
        let script = shellQuote(scriptURL.path)
        return "/usr/bin/clear; _wowsilicon_command=\"$(/bin/cat \(script))\"; "
            + "if [ -n \"$ZSH_VERSION\" ]; then print -s -- \"$_wowsilicon_command\"; "
            + "elif [ -n \"$BASH_VERSION\" ]; then history -s \"$_wowsilicon_command\"; fi; "
            + "/usr/bin/printf '%s\\n' \"$_wowsilicon_command\"; /bin/rm -f \(script); "
            + "eval \"$_wowsilicon_command\"; _wowsilicon_status=$?; unset _wowsilicon_command; "
            + "(exit $_wowsilicon_status)"
    }

    func makeShellCommand(
        gameURL: URL,
        x87Runtime: BundledX87Runtime.ResolvedRuntime?,
        wowURL: URL,
        wineExecutablePath: String,
        settings: VersionSettings,
        profileKind: GameProfileKind = .worldOfWarcraft
    ) -> String {
        let game = shellQuote(gameURL.path)
        let wow = shellQuote(wowURL.path)
        let wine = shellQuote(wineExecutablePath)

        if profileKind == .worldOfWarcraftX64 {
            return makeX64ShellCommand(game: game, wow: wow, wine: wine, settings: settings)
        }

        let mtlValue = settings.enableMetalHud ? "1" : "0"
        let spatialAudioMode = settings.spatializeStereo ? "fixed" : "off"
        let normalizeAudio = settings.normalizeAudio ? "1" : "0"
        let outputDeviceOverride = settings.audioOutputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_OUTPUT=0"
        let inputDeviceOverride = settings.audioInputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_INPUT=0"
        let dllOverride = settings.graphicsSettings.backend.wineDLLOverride
        let dyldLibraryPath = shellQuote(BundledWineRuntime.makeEnvironment()["DYLD_LIBRARY_PATH"] ?? "")
        let winePrefix = BundledWineRuntime.shellEnvironmentAssignment(
            key: "WINEPREFIX",
            value: WineRegistrySupport.winePrefixURL().path
        )
        let vulkanDriver = vulkanDriverShellAssignment(for: settings.graphicsSettings)
        let baseEnv = "\(winePrefix) DYLD_LIBRARY_PATH=\(dyldLibraryPath)\(vulkanDriver) WINE_LARGE_ADDRESS_AWARE=1 WINEDLLOVERRIDES=\(shellQuote(dllOverride))\(outputDeviceOverride)\(inputDeviceOverride) WOWSILICON_SPATIAL_AUDIO_MODE=\(spatialAudioMode) WOWSILICON_NORMALIZE_AUDIO=\(normalizeAudio) MTL_HUD_ENABLED=\(mtlValue) MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 DXVK_ASYNC=1"
        let custom = BundledWineRuntime.shellEnvironmentAssignments(settings.environmentVariables)
        let envPart = custom.isEmpty ? baseEnv : "\(custom) \(baseEnv)"

        if let x87Runtime {
            let binary = shellQuote(x87Runtime.executableURL.path)
            return "cd \(game) && \(x87Runtime.wineEnvironmentKey)=\(binary) \(envPart) \(wine) \(wow)"
        } else {
            return "cd \(game) && \(envPart) \(wine) \(wow)"
        }
    }

    /// Configuration proven by the BfA 8.3.7 spike: wined3d on MoltenVK, no DLL override, no x87,
    /// and the client's `-d3d11` argument. Nothing from the 32-bit pipeline is carried over.
    private func makeX64ShellCommand(game: String, wow: String, wine: String, settings: VersionSettings) -> String {
        let mtlValue = settings.enableMetalHud ? "1" : "0"
        let spatialAudioMode = settings.spatializeStereo ? "fixed" : "off"
        let normalizeAudio = settings.normalizeAudio ? "1" : "0"
        let outputDeviceOverride = settings.audioOutputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_OUTPUT=0"
        let inputDeviceOverride = settings.audioInputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_INPUT=0"
        let dyldLibraryPath = shellQuote(BundledWineRuntime.makeEnvironment()["DYLD_LIBRARY_PATH"] ?? "")
        let winePrefix = BundledWineRuntime.shellEnvironmentAssignment(
            key: "WINEPREFIX",
            value: WineRegistrySupport.winePrefixURL().path
        )
        let vulkanDriver = BundledWineRuntime.vulkanDriverShellAssignment(for: .moltenVK)
            .map { " \($0)" } ?? ""
        let baseEnv = "\(winePrefix) DYLD_LIBRARY_PATH=\(dyldLibraryPath)\(vulkanDriver) WINE_D3D_CONFIG=renderer=vulkan\(outputDeviceOverride)\(inputDeviceOverride) WOWSILICON_SPATIAL_AUDIO_MODE=\(spatialAudioMode) WOWSILICON_NORMALIZE_AUDIO=\(normalizeAudio) MTL_HUD_ENABLED=\(mtlValue)"
        let custom = BundledWineRuntime.shellEnvironmentAssignments(settings.environmentVariables)
        let envPart = custom.isEmpty ? baseEnv : "\(custom) \(baseEnv)"
        return "cd \(game) && \(envPart) \(wine) \(wow) -d3d11"
    }

    func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func shortcutSafeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let sanitized = String(result).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "Launch-WoW" : sanitized
    }

    func launchInstaller(installerURL: URL, version: GameVersion, completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void) {
        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            DispatchQueue.main.async { completion(.failure(.wineMissing(expectedPath))) }
            return
        }

        let installer = shellQuote(installerURL.path)
        let wine = shellQuote(wineExecutableURL.path)
        let dllOverride = version.settings.graphicsSettings.backend.wineDLLOverrideWithBuiltinFallback
        let dyldLibraryPath = shellQuote(BundledWineRuntime.makeEnvironment()["DYLD_LIBRARY_PATH"] ?? "")
        let winePrefix = BundledWineRuntime.shellEnvironmentAssignment(
            key: "WINEPREFIX",
            value: WineRegistrySupport.winePrefixURL().path
        )
        let custom = BundledWineRuntime.shellEnvironmentAssignments(version.settings.environmentVariables)
        let vulkanDriver = vulkanDriverShellAssignment(for: version.settings.graphicsSettings)
        let baseEnv = "\(winePrefix) DYLD_LIBRARY_PATH=\(dyldLibraryPath)\(vulkanDriver) WINEDLLOVERRIDES=\(shellQuote(dllOverride))"
        let envPart = custom.isEmpty ? baseEnv : "\(custom) \(baseEnv)"
        let shellCommand = "\(envPart) \(wine) \(installer)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellCommand]
        process.environment = BundledWineRuntime.makeEnvironment(
            customVariables: version.settings.environmentVariables
        )

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.untrackProcess(process)
                self.processDidTerminate?()
                completion(.success(()))
            }
        }

        do {
            try process.run()
            trackProcess(process)
        } catch {
            DispatchQueue.main.async { completion(.failure(.processLaunchFailed(error.localizedDescription))) }
        }
    }

    func launchWineConfiguration(
        customVariables: String,
        completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void
    ) {
        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            DispatchQueue.main.async { completion(.failure(.wineMissing(expectedPath))) }
            return
        }

        let process = Process()
        process.executableURL = wineExecutableURL
        process.arguments = ["winecfg"]
        process.environment = BundledWineRuntime.makeEnvironment(customVariables: customVariables)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.untrackProcess(process)
                self?.processDidTerminate?()
            }
        }

        do {
            try process.run()
            trackProcess(process)
            DispatchQueue.main.async { completion(.success(())) }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(.processLaunchFailed(error.localizedDescription)))
            }
        }
    }

    func launchWineTerminal(
        customVariables: String,
        completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void
    ) {
        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            DispatchQueue.main.async { completion(.failure(.wineMissing(expectedPath))) }
            return
        }

        let environment = BundledWineRuntime.makeEnvironment(customVariables: customVariables)
        let winePrefix = BundledWineRuntime.shellEnvironmentAssignment(
            key: "WINEPREFIX",
            value: environment["WINEPREFIX"] ?? WineRegistrySupport.winePrefixURL().path
        )
        let dyldLibraryPath = BundledWineRuntime.shellEnvironmentAssignment(
            key: "DYLD_LIBRARY_PATH",
            value: environment["DYLD_LIBRARY_PATH"] ?? ""
        )
        let wineBinURL = wineExecutableURL.deletingLastPathComponent()
        let path = BundledWineRuntime.shellEnvironmentAssignment(
            key: "PATH",
            value: "\(wineBinURL.path):\(environment["PATH"] ?? "")"
        )
        let custom = BundledWineRuntime.shellEnvironmentAssignments(customVariables)
        let customExport = custom.isEmpty ? "" : "export \(custom); "
        let shellCommand = "\(customExport)export \(winePrefix) \(dyldLibraryPath) \(path); "
            + "clear; printf 'SiloWow Wine terminal\\nBottle: %s\\n\\n' \"$WINEPREFIX\""

        do {
            try launchTerminalCommand(shellCommand)
            DispatchQueue.main.async { completion(.success(())) }
        } catch let error as LaunchServiceError {
            DispatchQueue.main.async { completion(.failure(error)) }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(.processLaunchFailed(error.localizedDescription)))
            }
        }
    }

    @MainActor
    func launchThirdPartyLauncher(version: GameVersion, completion: @escaping @Sendable (Result<Void, LaunchServiceError>) -> Void) {
        if version.settings.graphicsSettings.backend == .d9vk {
            let driver = version.settings.graphicsSettings.vulkanDriver
            guard driver.isSupportedOnCurrentMacOS else {
                completion(.failure(.vulkanDriverUnsupported(driver.displayName)))
                return
            }
            if driver == .kosmicKrisp,
               BundledWineRuntime.vulkanDriverManifestURL(for: driver) == nil {
                completion(.failure(.vulkanDriverMissing(driver)))
                return
            }
        }

        let exePath = version.launcherExePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !exePath.isEmpty else {
            DispatchQueue.main.async { completion(.failure(.executableMissing("No launcher configured"))) }
            return
        }

        guard let wineExecutableURL = BundledWineRuntime.wineExecutableURL() else {
            let expectedPath = BundledWineRuntime.rootURL()?
                .appendingPathComponent("bin/wine", isDirectory: false).path ?? "Contents/Resources/Wine/bin/wine"
            DispatchQueue.main.async { completion(.failure(.wineMissing(expectedPath))) }
            return
        }

        let spatialAudioControlURL = SpatialAudioService.controlURL()
        let normalizeAudioControlURL = SpatialAudioService.normalizeAudioControlURL()
        do {
            try SpatialAudioService.setEnabled(
                version.settings.spatializeStereo,
                controlURL: spatialAudioControlURL
            )
            try SpatialAudioService.setNormalizeAudio(
                version.settings.normalizeAudio,
                controlURL: normalizeAudioControlURL
            )
        } catch {
            DispatchQueue.main.async {
                completion(.failure(.processLaunchFailed(error.localizedDescription)))
            }
            return
        }

        let exeURL = URL(fileURLWithPath: exePath)
        let launcherDir = shellQuote(exeURL.deletingLastPathComponent().path)
        let exeName = shellQuote(exeURL.lastPathComponent)
        let wine = shellQuote(wineExecutableURL.path)

        let mtlValue = version.settings.enableMetalHud ? "1" : "0"
        let spatialAudioMode = version.settings.spatializeStereo ? "fixed" : "off"
        let normalizeAudio = version.settings.normalizeAudio ? "1" : "0"
        let outputDeviceOverride = version.settings.audioOutputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_OUTPUT=0"
        let inputDeviceOverride = version.settings.audioInputDeviceID.isEmpty ? "" : " WOWSILICON_FOLLOW_SYSTEM_INPUT=0"
        let dllOverride = version.settings.graphicsSettings.backend.wineDLLOverrideWithBuiltinFallback
        let dyldLibraryPath = shellQuote(BundledWineRuntime.makeEnvironment()["DYLD_LIBRARY_PATH"] ?? "")
        let winePrefix = BundledWineRuntime.shellEnvironmentAssignment(
            key: "WINEPREFIX",
            value: WineRegistrySupport.winePrefixURL().path
        )
        let vulkanDriver = vulkanDriverShellAssignment(for: version.settings.graphicsSettings)
        let baseEnv = "\(winePrefix) DYLD_LIBRARY_PATH=\(dyldLibraryPath)\(vulkanDriver) WINE_D3D_CONFIG=renderer=vulkan WINE_LARGE_ADDRESS_AWARE=1 WINEDLLOVERRIDES=\(shellQuote(dllOverride))\(outputDeviceOverride)\(inputDeviceOverride) WOWSILICON_SPATIAL_AUDIO_MODE=\(spatialAudioMode) WOWSILICON_NORMALIZE_AUDIO=\(normalizeAudio) MTL_HUD_ENABLED=\(mtlValue) MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 DXVK_ASYNC=1"
        let custom = BundledWineRuntime.shellEnvironmentAssignments(version.settings.environmentVariables)
        let envPart = custom.isEmpty ? baseEnv : "\(custom) \(baseEnv)"

        let shellCommand = "cd \(launcherDir) && \(envPart) \(wine) \(exeName) --disable-gpu --in-process-gpu"

        let focusID = startWineApplicationFocusObservation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellCommand]
        process.environment = BundledWineRuntime.makeEnvironment(
            customVariables: version.settings.environmentVariables
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.cancelWineApplicationFocusObservation(id: focusID)
                self.untrackProcess(process)
                self.processDidTerminate?()
            }
        }

        do {
            try process.run()
            trackProcess(process)
            DispatchQueue.main.async { completion(.success(())) }
        } catch {
            cancelWineApplicationFocusObservation(id: focusID)
            DispatchQueue.main.async { completion(.failure(.processLaunchFailed(error.localizedDescription))) }
        }
    }

    private func vulkanDriverShellAssignment(for settings: GraphicsSettings) -> String {
        guard settings.backend == .d9vk,
              let assignment = BundledWineRuntime.vulkanDriverShellAssignment(
                for: settings.vulkanDriver
              ) else {
            return ""
        }
        return " \(assignment)"
    }

    func checkVersionMismatch(for version: GameVersion) -> (base: String, tweaked: String)? {
        let trimmedGame = version.gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGame.isEmpty else { return nil }
        
        let gameURL = URL(fileURLWithPath: trimmedGame, isDirectory: true)
        let wowURL = gameURL.appendingPathComponent("WoW.exe")
        let tweakedURL = gameURL.appendingPathComponent("WoW_tweaked.exe")
        
        guard fileManager.fileExists(atPath: wowURL.path),
              fileManager.fileExists(atPath: tweakedURL.path) else {
            return nil
        }
        
        guard let baseVersion = BinaryVersionReader.readWoWVersion(from: wowURL),
              !baseVersion.isEmpty,
              let tweakedVersion = BinaryVersionReader.readWoWVersion(from: tweakedURL),
              !tweakedVersion.isEmpty else {
            return nil
        }
        
        if baseVersion != tweakedVersion {
            return (baseVersion, tweakedVersion)
        }
        
        // Also check build number just in case the version string is the same but build changed
        let baseBuild = BinaryVersionReader.readWoWBuild(from: wowURL) ?? ""
        let tweakedBuild = BinaryVersionReader.readWoWBuild(from: tweakedURL) ?? ""
        
        if !baseBuild.isEmpty && !tweakedBuild.isEmpty && baseBuild != tweakedBuild {
            // Trim to show just the build part if it's long
            let b1 = baseBuild.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? baseBuild
            let b2 = tweakedBuild.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? tweakedBuild
            return (b1, b2)
        }
        
        return nil
    }

    private func patchesAppearValid(for version: GameVersion) -> Bool {
        let descriptor = PatchingStatusChecker.evaluateGamePatch(for: version)
        return descriptor.applied
    }

    @MainActor
    private func startWineApplicationFocusObservation(additionalExecutableURL: URL? = nil) -> UUID {
        cancelWineApplicationFocusObservation()
        let id = UUID()
        guard let runtimeRootURL = BundledWineRuntime.rootURL() else { return id }

        let matcher = WineApplicationFocusMatcher(
            baselineProcessIDs: Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)),
            runtimeRootURL: runtimeRootURL,
            additionalExecutableURLs: Set([additionalExecutableURL].compactMap { $0 })
        )
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.activateWineApplicationIfMatching(application, observationID: id)
            }
        }
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelWineApplicationFocusObservation(id: id)
            }
        }
        focusObservation = FocusObservation(
            id: id,
            matcher: matcher,
            observer: observer,
            timeout: timeout
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        return id
    }

    @MainActor
    private func activateWineApplicationIfMatching(
        _ application: NSRunningApplication,
        observationID: UUID
    ) {
        guard var observation = focusObservation,
              observation.id == observationID,
              observation.matcher.accepts(
                processIdentifier: application.processIdentifier,
                executableURL: application.executableURL
              ) else {
            return
        }

        cancelWineApplicationFocusObservation(id: observationID)
        NSApplication.shared.yieldActivation(to: application)
        application.activate(from: .current, options: [])
    }

    @MainActor
    private func cancelWineApplicationFocusObservation(id: UUID? = nil) {
        guard let observation = focusObservation,
              id == nil || observation.id == id else {
            return
        }
        NSWorkspace.shared.notificationCenter.removeObserver(observation.observer)
        observation.timeout.cancel()
        focusObservation = nil
    }

    private func trackProcess(_ process: Process) {
        processQueue.sync {
            runningProcesses.append(process)
        }
    }

    private func untrackProcess(_ process: Process) {
        processQueue.sync {
            runningProcesses.removeAll { $0 === process }
        }
    }

    @discardableResult
    static func cleanWDBIfEnabled(
        _ enabled: Bool,
        at gameURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard enabled else { return [] }

        let candidates = [
            gameURL.appendingPathComponent("WDB", isDirectory: true),
            gameURL.appendingPathComponent("Cache", isDirectory: true).appendingPathComponent("WDB", isDirectory: true)
        ]
        var removed: [URL] = []
        var failures: [String] = []

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            try Task.checkCancellation()
            do {
                try fileManager.removeItem(at: url)
                removed.append(url)
            } catch {
                failures.append("\(url.path): \(error.localizedDescription)")
            }
        }

        guard failures.isEmpty else {
            throw LaunchServiceError.wdbCleanupFailed(failures.joined(separator: "\n"))
        }
        return removed
    }

    // MARK: - Force quit

    static func forceQuitWine() {
        if let wineserverURL = BundledWineRuntime.wineserverExecutableURL() {
            _ = try? ProcessRunner.run(
                executablePath: wineserverURL.path,
                arguments: ["-k"],
                environment: BundledWineRuntime.makeEnvironment(),
                timeout: 5
            )
            if WineProcessMonitor.waitForApplicationProcessExit(timeout: 2) == 0 {
                return
            }
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier

        // A Wine helper can create another child while the session is being torn down.
        // Rescan briefly so the button also catches that final helper process.
        for pass in 0..<3 {
            guard let processIDs = WineProcessMonitor.currentProcessIDs() else { return }
            for processID in processIDs where processID != currentProcessID {
                kill(processID, SIGKILL)
            }
            if pass < 2 {
                usleep(250_000)
            }
        }
    }
}
