import Foundation

// MARK: - Graphics settings

enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    case d9vk
    case mtld3d

    var displayName: String {
        switch self {
        case .d9vk: return "DXVK"
        case .mtld3d: return "MTLD3D"
        }
    }

    var wineDLLOverride: String {
        switch self {
        case .d9vk: return "d3d9=n"
        case .mtld3d: return "d3d9=b"
        }
    }

    var wineDLLOverrideWithBuiltinFallback: String {
        switch self {
        case .d9vk: return "d3d9=n,b"
        case .mtld3d: return "d3d9=b"
        }
    }
}

enum VulkanDriver: String, Codable, CaseIterable, Sendable {
    case moltenVK = "moltenvk"
    case kosmicKrisp = "kosmickrisp"

    static let kosmicKrispMinimumMacOSMajorVersion = 26

    var displayName: String {
        switch self {
        case .moltenVK: return "MoltenVK"
        case .kosmicKrisp: return "KosmicKrisp"
        }
    }

    var manifestFileName: String {
        switch self {
        case .moltenVK: return "MoltenVK_icd.json"
        case .kosmicKrisp: return "KosmicKrisp_icd.json"
        }
    }

    func isSupported(onMacOS version: OperatingSystemVersion) -> Bool {
        self != .kosmicKrisp || version.majorVersion >= Self.kosmicKrispMinimumMacOSMajorVersion
    }

    var isSupportedOnCurrentMacOS: Bool {
        isSupported(onMacOS: ProcessInfo.processInfo.operatingSystemVersion)
    }
}

enum X87Backend: String, Codable, CaseIterable, Sendable {
    case disabled
    case rosettaX87 = "rosettax87"
    case x87Sidecar = "x87sidecar"

    var displayName: String {
        switch self {
        case .disabled: return "Stock Rosetta"
        case .rosettaX87: return "rosettax87 JIT"
        case .x87Sidecar: return "x87sidecar"
        }
    }
}

enum WindowMode: String, Codable, CaseIterable, Sendable {
    case windowed
    case fullscreen

    var displayName: String {
        switch self {
        case .windowed: return "Windowed"
        case .fullscreen: return "Fullscreen"
        }
    }
}

enum Multisampling: String, Codable, CaseIterable, Sendable {
    case off
    case x2
    case x4
    case x8

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .x2: return "2x"
        case .x4: return "4x"
        case .x8: return "8x"
        }
    }

    var configValue: Int? {
        switch self {
        case .off: return nil
        case .x2: return 2
        case .x4: return 4
        case .x8: return 8
        }
    }
}

enum TextureFiltering: String, Codable, CaseIterable, Sendable {
    case bilinear
    case trilinear
    case anisotropicX16

    var displayName: String {
        switch self {
        case .bilinear: return "Bilinear"
        case .trilinear: return "Trilinear"
        case .anisotropicX16: return "Anisotropic 16x"
        }
    }
}

enum ShadowQuality: String, Codable, CaseIterable, Sendable {
    case off
    case low
    case high

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .high: return "High"
        }
    }
}

struct GraphicsSettings: Codable, Equatable, Sendable {
    var backend: GraphicsBackend
    var vulkanDriver: VulkanDriver
    var hdrEnabled: Bool
    var windowMode: WindowMode
    var resolution: String
    var refreshRate: Int
    var vsync: Bool
    var multisampling: Multisampling
    var textureFiltering: TextureFiltering
    var specular: Bool
    var projectedTextures: Bool
    var viewDistance: Int
    var groundEffectDensity: Int
    var weatherDensity: Int
    var particleDensity: Double
    var shadowQuality: ShadowQuality

    static let `default` = GraphicsSettings(
        backend: .d9vk,
        vulkanDriver: .moltenVK,
        hdrEnabled: false,
        windowMode: .windowed,
        resolution: "",
        refreshRate: 60,
        vsync: false,
        multisampling: .x2,
        textureFiltering: .anisotropicX16,
        specular: true,
        projectedTextures: true,
        viewDistance: 777,
        groundEffectDensity: 3,
        weatherDensity: 3,
        particleDensity: 1.0,
        shadowQuality: .off
    )

    static let commonResolutions = [
        "1280x720", "1280x800", "1440x900", "1600x900", "1680x1050",
        "1920x1080", "1920x1200", "2560x1440", "2560x1600", "3840x2160"
    ]

    static let commonRefreshRates = [30, 60, 120, 144, 165, 240]

    enum CodingKeys: String, CodingKey {
        case backend, vulkanDriver, hdrEnabled, windowMode, resolution, refreshRate, vsync, multisampling
        case textureFiltering, specular, projectedTextures
        case viewDistance, groundEffectDensity, weatherDensity, particleDensity, shadowQuality
    }

    init(
        backend: GraphicsBackend = .d9vk,
        vulkanDriver: VulkanDriver = .moltenVK,
        hdrEnabled: Bool = false,
        windowMode: WindowMode = .windowed,
        resolution: String = "",
        refreshRate: Int = 60,
        vsync: Bool = false,
        multisampling: Multisampling = .x2,
        textureFiltering: TextureFiltering = .anisotropicX16,
        specular: Bool = true,
        projectedTextures: Bool = true,
        viewDistance: Int = 777,
        groundEffectDensity: Int = 3,
        weatherDensity: Int = 3,
        particleDensity: Double = 1.0,
        shadowQuality: ShadowQuality = .off
    ) {
        self.backend = backend
        self.vulkanDriver = vulkanDriver
        self.hdrEnabled = hdrEnabled
        self.windowMode = windowMode
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.vsync = vsync
        self.multisampling = multisampling
        self.textureFiltering = textureFiltering
        self.specular = specular
        self.projectedTextures = projectedTextures
        self.viewDistance = viewDistance
        self.groundEffectDensity = groundEffectDensity
        self.weatherDensity = weatherDensity
        self.particleDensity = particleDensity
        self.shadowQuality = shadowQuality
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        backend = try c.decodeIfPresent(GraphicsBackend.self, forKey: .backend) ?? .d9vk
        vulkanDriver = try c.decodeIfPresent(VulkanDriver.self, forKey: .vulkanDriver) ?? .moltenVK
        hdrEnabled = try c.decodeIfPresent(Bool.self, forKey: .hdrEnabled) ?? false
        windowMode = try c.decodeIfPresent(WindowMode.self, forKey: .windowMode) ?? .windowed
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution) ?? ""
        refreshRate = try c.decodeIfPresent(Int.self, forKey: .refreshRate) ?? 60
        vsync = try c.decodeIfPresent(Bool.self, forKey: .vsync) ?? false
        multisampling = try c.decodeIfPresent(Multisampling.self, forKey: .multisampling) ?? .x2
        textureFiltering = try c.decodeIfPresent(TextureFiltering.self, forKey: .textureFiltering) ?? .anisotropicX16
        specular = try c.decodeIfPresent(Bool.self, forKey: .specular) ?? true
        projectedTextures = try c.decodeIfPresent(Bool.self, forKey: .projectedTextures) ?? true
        viewDistance = try c.decodeIfPresent(Int.self, forKey: .viewDistance) ?? 777
        // Migrate from old enum string ("off"/"low"/"medium"/"high") to Int (0–3)
        if let intVal = try? c.decodeIfPresent(Int.self, forKey: .groundEffectDensity) {
            groundEffectDensity = intVal
        } else if let strVal = try? c.decodeIfPresent(String.self, forKey: .groundEffectDensity) {
            switch strVal {
            case "off":    groundEffectDensity = 0
            case "low":    groundEffectDensity = 1
            case "medium": groundEffectDensity = 2
            default:       groundEffectDensity = 3
            }
        } else {
            groundEffectDensity = 3
        }
        weatherDensity = try c.decodeIfPresent(Int.self, forKey: .weatherDensity) ?? 3
        particleDensity = try c.decodeIfPresent(Double.self, forKey: .particleDensity) ?? 1.0
        shadowQuality = try c.decodeIfPresent(ShadowQuality.self, forKey: .shadowQuality) ?? .off
    }
}

// MARK: - Version settings

struct VersionSettings: Codable, Equatable, Sendable {
    var enableVanillaTweaks: Bool
    var remapOptionAsAlt: Bool
    var autoDeleteWdb: Bool
    var enableMetalHud: Bool
    var showTerminalNormally: Bool
    var environmentVariables: String
    var vanillaTweaksParameters: String
    var cursorSizeMultiplier: Int
    var graphicsSettings: GraphicsSettings
    var enableLibSiliconPatch: Bool
    var userDisabledLibSiliconPatch: Bool
    var x87Backend: X87Backend
    var audioOutputDeviceID: String
    var audioInputDeviceID: String
    var spatializeStereo: Bool
    var normalizeAudio: Bool
    /// Battle.net portal (`host:port`) written to `WTF/Config.wtf` before each launch of an x64
    /// client. Empty means "leave Config.wtf alone".
    var portal: String
    /// Client text / voice-over locale (e.g. `frFR`) written to Config.wtf for x64 clients.
    /// Empty means "leave Config.wtf alone".
    var textLocale: String
    var audioLocale: String

    var enableRosettaX87: Bool {
        get { x87Backend != .disabled }
        set { x87Backend = newValue ? .rosettaX87 : .disabled }
    }

    init(
        enableVanillaTweaks: Bool = false,
        remapOptionAsAlt: Bool = false,
        autoDeleteWdb: Bool = true,
        enableMetalHud: Bool = false,
        showTerminalNormally: Bool = false,
        environmentVariables: String = "",
        vanillaTweaksParameters: String = "",
        cursorSizeMultiplier: Int = 1,
        graphicsSettings: GraphicsSettings = GraphicsSettings(),
        enableLibSiliconPatch: Bool = false,
        userDisabledLibSiliconPatch: Bool = false,
        enableRosettaX87: Bool = true,
        x87Backend: X87Backend? = nil,
        audioOutputDeviceID: String = "",
        audioInputDeviceID: String = "",
        spatializeStereo: Bool = false,
        normalizeAudio: Bool = false,
        portal: String = "",
        textLocale: String = "",
        audioLocale: String = ""
    ) {
        self.enableVanillaTweaks = enableVanillaTweaks
        self.remapOptionAsAlt = remapOptionAsAlt
        self.autoDeleteWdb = autoDeleteWdb
        self.enableMetalHud = enableMetalHud
        self.showTerminalNormally = showTerminalNormally
        self.environmentVariables = environmentVariables
        self.vanillaTweaksParameters = vanillaTweaksParameters
        self.cursorSizeMultiplier = cursorSizeMultiplier
        self.graphicsSettings = graphicsSettings
        self.enableLibSiliconPatch = enableLibSiliconPatch
        self.userDisabledLibSiliconPatch = userDisabledLibSiliconPatch
        self.x87Backend = x87Backend ?? (enableRosettaX87 ? .rosettaX87 : .disabled)
        self.audioOutputDeviceID = audioOutputDeviceID
        self.audioInputDeviceID = audioInputDeviceID
        self.spatializeStereo = spatializeStereo
        self.normalizeAudio = normalizeAudio
        self.portal = portal
        self.textLocale = textLocale
        self.audioLocale = audioLocale
    }

    enum CodingKeys: String, CodingKey {
        case enableVanillaTweaks, remapOptionAsAlt, autoDeleteWdb, enableMetalHud
        case showTerminalNormally, environmentVariables
        case vanillaTweaksParameters, cursorSizeMultiplier
        case graphicsSettings
        case enableLibSiliconPatch, userDisabledLibSiliconPatch
        case x87Backend, enableRosettaX87
        case audioOutputDeviceID, audioInputDeviceID
        case spatialAudioMode, spatializeStereo
        case normalizeAudio = "normalize_audio"
        case portal, textLocale, audioLocale
        // Legacy keys kept for migration only
        case nightMode
        case reduceTerrainDistance, setMultisampleTo2x, setShadowLOD0, userDisabledShadowLOD
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableVanillaTweaks = try container.decodeIfPresent(Bool.self, forKey: .enableVanillaTweaks) ?? false
        remapOptionAsAlt = try container.decodeIfPresent(Bool.self, forKey: .remapOptionAsAlt) ?? false
        autoDeleteWdb = try container.decodeIfPresent(Bool.self, forKey: .autoDeleteWdb) ?? true
        enableMetalHud = try container.decodeIfPresent(Bool.self, forKey: .enableMetalHud) ?? false
        showTerminalNormally = try container.decodeIfPresent(Bool.self, forKey: .showTerminalNormally) ?? false
        environmentVariables = try container.decodeIfPresent(String.self, forKey: .environmentVariables) ?? ""
        vanillaTweaksParameters = try container.decodeIfPresent(String.self, forKey: .vanillaTweaksParameters) ?? ""
        cursorSizeMultiplier = try container.decodeIfPresent(Int.self, forKey: .cursorSizeMultiplier) ?? 1
        enableLibSiliconPatch = try container.decodeIfPresent(Bool.self, forKey: .enableLibSiliconPatch) ?? false
        userDisabledLibSiliconPatch = try container.decodeIfPresent(Bool.self, forKey: .userDisabledLibSiliconPatch) ?? false
        if let backend = try container.decodeIfPresent(X87Backend.self, forKey: .x87Backend) {
            x87Backend = backend
        } else {
            let enabled = try container.decodeIfPresent(Bool.self, forKey: .enableRosettaX87) ?? true
            x87Backend = enabled ? .rosettaX87 : .disabled
        }
        audioOutputDeviceID = try container.decodeIfPresent(String.self, forKey: .audioOutputDeviceID) ?? ""
        audioInputDeviceID = try container.decodeIfPresent(String.self, forKey: .audioInputDeviceID) ?? ""
        if let enabled = try container.decodeIfPresent(Bool.self, forKey: .spatializeStereo) {
            spatializeStereo = enabled
        } else {
            let interimMode = try container.decodeIfPresent(String.self, forKey: .spatialAudioMode)
            spatializeStereo = interimMode == "fixed" || interimMode == "head_tracked"
        }
        normalizeAudio = try container.decodeIfPresent(Bool.self, forKey: .normalizeAudio)
            ?? container.decodeIfPresent(Bool.self, forKey: .nightMode)
            ?? false
        portal = try container.decodeIfPresent(String.self, forKey: .portal) ?? ""
        textLocale = try container.decodeIfPresent(String.self, forKey: .textLocale) ?? ""
        audioLocale = try container.decodeIfPresent(String.self, forKey: .audioLocale) ?? ""

        if let gs = try container.decodeIfPresent(GraphicsSettings.self, forKey: .graphicsSettings) {
            graphicsSettings = gs
        } else {
            // Migrate from legacy bool fields
            var gs = GraphicsSettings()
            if let reduceTerrain = try container.decodeIfPresent(Bool.self, forKey: .reduceTerrainDistance), reduceTerrain {
                gs.viewDistance = 177
            }
            if let multisample = try container.decodeIfPresent(Bool.self, forKey: .setMultisampleTo2x), multisample {
                gs.multisampling = .x2
            }
            if let shadowLOD = try container.decodeIfPresent(Bool.self, forKey: .setShadowLOD0), shadowLOD {
                gs.shadowQuality = .off
            }
            graphicsSettings = gs
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enableVanillaTweaks, forKey: .enableVanillaTweaks)
        try container.encode(remapOptionAsAlt, forKey: .remapOptionAsAlt)
        try container.encode(autoDeleteWdb, forKey: .autoDeleteWdb)
        try container.encode(enableMetalHud, forKey: .enableMetalHud)
        try container.encode(showTerminalNormally, forKey: .showTerminalNormally)
        try container.encode(environmentVariables, forKey: .environmentVariables)
        try container.encode(vanillaTweaksParameters, forKey: .vanillaTweaksParameters)
        try container.encode(cursorSizeMultiplier, forKey: .cursorSizeMultiplier)
        try container.encode(graphicsSettings, forKey: .graphicsSettings)
        try container.encode(enableLibSiliconPatch, forKey: .enableLibSiliconPatch)
        try container.encode(userDisabledLibSiliconPatch, forKey: .userDisabledLibSiliconPatch)
        try container.encode(x87Backend, forKey: .x87Backend)
        try container.encode(enableRosettaX87, forKey: .enableRosettaX87)
        try container.encode(audioOutputDeviceID, forKey: .audioOutputDeviceID)
        try container.encode(audioInputDeviceID, forKey: .audioInputDeviceID)
        try container.encode(spatializeStereo, forKey: .spatializeStereo)
        try container.encode(normalizeAudio, forKey: .normalizeAudio)
        try container.encode(portal, forKey: .portal)
        try container.encode(textLocale, forKey: .textLocale)
        try container.encode(audioLocale, forKey: .audioLocale)
    }

    func mergedWithDefaults(_ defaults: VersionSettings) -> VersionSettings {
        var merged = self
        if defaults.enableLibSiliconPatch && !merged.userDisabledLibSiliconPatch {
            merged.enableLibSiliconPatch = true
        }
        return merged
    }
}

enum OptimizationLevel: String, Codable, Sendable {
    case low
    case mid
    case high
}

/// Profile family. Decoding is tolerant: a raw value this build does not know is kept in
/// `.unknown` and written back unchanged, so a file saved by a newer build never loses a profile.
enum GameProfileKind: Codable, Sendable, Equatable, Hashable {
    case worldOfWarcraft
    case genericD3D9
    /// 64-bit WoW client (BfA 8.x): no 32-bit patch DLLs, no x87, wined3d Vulkan renderer.
    case worldOfWarcraftX64
    /// A kind written by another build. The profile is kept but cannot be launched.
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "world_of_warcraft": self = .worldOfWarcraft
        case "generic_d3d9": self = .genericD3D9
        case "world_of_warcraft_x64": self = .worldOfWarcraftX64
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .worldOfWarcraft: return "world_of_warcraft"
        case .genericD3D9: return "generic_d3d9"
        case .worldOfWarcraftX64: return "world_of_warcraft_x64"
        case .unknown(let value): return value
        }
    }

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct GameVersion: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var profileKind: GameProfileKind
    var wowVersion: String
    var gamePath: String
    var executableName: String
    var supportsVanillaTweaks: Bool
    var supportsDLLLoading: Bool
    var usesRosettaPatching: Bool
    var optimizationLevel: OptimizationLevel
    var settings: VersionSettings
    var launcherExePath: String
    var wantsLauncher: Bool

    var hasLauncher: Bool { !launcherExePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// True only for the 32-bit WoW client families (1.12 / 2.4.3 / 3.3.5). The x64 profile is
    /// deliberately excluded: it shares none of their patching, realmlist or graphics pipeline.
    var isWorldOfWarcraft: Bool { profileKind == .worldOfWarcraft }
    var isWorldOfWarcraftX64: Bool { profileKind == .worldOfWarcraftX64 }
    /// AddonService only reads `Interface/AddOns` and is independent of the client version.
    var supportsAddons: Bool { isWorldOfWarcraft || isWorldOfWarcraftX64 }
    /// The 3.3.5 `realmlist.wtf` format does not apply to 8.x clients.
    var supportsRealmlist: Bool { isWorldOfWarcraft }
    var supportsCustomGraphicsSettings: Bool { isWorldOfWarcraft }

    var libSiliconPatchSubdirectory: String? {
        switch wowVersion {
        case "1.12.1": return "Patching/libSiliconPatch/vanilla"
        case "3.3.5a": return "Patching/libSiliconPatch/wotlk"
        default: return nil
        }
    }

    var gameDirectoryURL: URL? {
        let trimmed = gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) {
            if isDir.boolValue {
                return URL(fileURLWithPath: trimmed, isDirectory: true)
            } else {
                return URL(fileURLWithPath: trimmed).deletingLastPathComponent()
            }
        }
        let url = URL(fileURLWithPath: trimmed)
        if url.pathExtension.lowercased() == "exe" {
            return url.deletingLastPathComponent()
        }
        return url
    }

    var gameDirectoryPath: String? {
        gameDirectoryURL?.path
    }

    var gameExecutableURL: URL? {
        let trimmed = gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir) {
            if !isDir.boolValue {
                return URL(fileURLWithPath: trimmed)
            } else {
                let dirURL = URL(fileURLWithPath: trimmed, isDirectory: true)
                let exeURL = dirURL.appendingPathComponent(executableName)
                if FileManager.default.fileExists(atPath: exeURL.path) {
                    return exeURL
                }
                let wowExe = dirURL.appendingPathComponent("WoW.exe")
                if FileManager.default.fileExists(atPath: wowExe.path) {
                    return wowExe
                }
                return exeURL
            }
        }
        let url = URL(fileURLWithPath: trimmed)
        if url.pathExtension.lowercased() == "exe" {
            return url
        }
        return url.appendingPathComponent(executableName)
    }

    var gameExecutablePath: String? {
        gameExecutableURL?.path
    }

    var effectiveExecutableName: String {
        let trimmed = gamePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return executableName }
        let url = URL(fileURLWithPath: trimmed)
        if url.pathExtension.lowercased() == "exe" {
            return url.lastPathComponent
        }
        return executableName
    }

    init(
        id: String,
        displayName: String,
        profileKind: GameProfileKind = .worldOfWarcraft,
        wowVersion: String,
        gamePath: String = "",
        executableName: String,
        supportsVanillaTweaks: Bool,
        supportsDLLLoading: Bool,
        usesRosettaPatching: Bool,
        optimizationLevel: OptimizationLevel = .low,
        settings: VersionSettings = VersionSettings(),
        launcherExePath: String = "",
        wantsLauncher: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.profileKind = profileKind
        self.wowVersion = wowVersion
        self.gamePath = gamePath
        self.executableName = executableName
        self.supportsVanillaTweaks = supportsVanillaTweaks
        self.supportsDLLLoading = supportsDLLLoading
        self.usesRosettaPatching = usesRosettaPatching
        self.optimizationLevel = optimizationLevel
        self.settings = settings
        self.launcherExePath = launcherExePath
        self.wantsLauncher = wantsLauncher
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case profileKind = "profile_kind"
        case wowVersion = "wow_version"
        case gamePath = "game_path"
        case executableName
        case supportsVanillaTweaks = "supports_vanilla_tweaks"
        case supportsDLLLoading = "supports_dll_loading"
        case usesRosettaPatching = "uses_rosetta_patching"
        case optimizationLevel = "optimization_level"
        case settings
        case launcherExePath = "launcher_exe_path"
        case wantsLauncher = "wants_launcher"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        profileKind = try container.decodeIfPresent(GameProfileKind.self, forKey: .profileKind) ?? .worldOfWarcraft
        wowVersion = try container.decode(String.self, forKey: .wowVersion)
        gamePath = try container.decodeIfPresent(String.self, forKey: .gamePath) ?? ""
        executableName = try container.decodeIfPresent(String.self, forKey: .executableName) ?? "WoW.exe"
        supportsVanillaTweaks = try container.decodeIfPresent(Bool.self, forKey: .supportsVanillaTweaks) ?? false
        supportsDLLLoading = try container.decodeIfPresent(Bool.self, forKey: .supportsDLLLoading) ?? false
        usesRosettaPatching = try container.decodeIfPresent(Bool.self, forKey: .usesRosettaPatching) ?? false
        optimizationLevel = try container.decodeIfPresent(OptimizationLevel.self, forKey: .optimizationLevel) ?? .low
        settings = try container.decodeIfPresent(VersionSettings.self, forKey: .settings) ?? VersionSettings()
        launcherExePath = try container.decodeIfPresent(String.self, forKey: .launcherExePath) ?? ""
        wantsLauncher = try container.decodeIfPresent(Bool.self, forKey: .wantsLauncher) ?? false
    }

    mutating func syncCapabilities(with defaults: GameVersion) {
        profileKind = defaults.profileKind
        executableName = defaults.executableName
        supportsVanillaTweaks = defaults.supportsVanillaTweaks
        supportsDLLLoading = defaults.supportsDLLLoading
        usesRosettaPatching = defaults.usesRosettaPatching
        optimizationLevel = defaults.optimizationLevel

        if !supportsVanillaTweaks {
            settings.enableVanillaTweaks = false
        }
    }
}

struct VersionManager: Codable, Sendable {
    var currentVersionID: String
    var versions: [String: GameVersion]

    static let defaultCurrentVersionID = "vanillasilicon"
    static let genericD3D9TemplateID = "genericd3d9"
    static let defaultOrder = [
        "vanillasilicon",
        "burningsilicon",
        "wrathsilicon"
    ]

    static let defaultVersions: [String: GameVersion] = [
        "vanillasilicon": GameVersion(
            id: "vanillasilicon",
            displayName: "VanillaSilicon (1.12.1)",
            wowVersion: "1.12.1",
            executableName: "WoW.exe",
            supportsVanillaTweaks: true,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            optimizationLevel: .high,
            settings: VersionSettings(autoDeleteWdb: true, enableLibSiliconPatch: true)
        ),
        "burningsilicon": GameVersion(
            id: "burningsilicon",
            displayName: "BurningSilicon (2.4.3)",
            wowVersion: "2.4.3",
            executableName: "WoW.exe",
            supportsVanillaTweaks: false,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            optimizationLevel: .mid,
            settings: VersionSettings(autoDeleteWdb: true)
        ),
        "wrathsilicon": GameVersion(
            id: "wrathsilicon",
            displayName: "WrathSilicon (3.3.5a)",
            wowVersion: "3.3.5a",
            executableName: "WoW.exe",
            supportsVanillaTweaks: false,
            supportsDLLLoading: true,
            usesRosettaPatching: true,
            optimizationLevel: .high,
            settings: VersionSettings(autoDeleteWdb: true, enableLibSiliconPatch: true)
        )
    ]

    static let bfa837X64TemplateID = "bfa837x64"

    /// Not part of `defaultVersions`: like the generic template, it is only created on demand.
    static let bfa837X64Template = GameVersion(
        id: bfa837X64TemplateID,
        displayName: "Battle for Azeroth 8.3.7 (x64)",
        profileKind: .worldOfWarcraftX64,
        wowVersion: "8.3.7",
        executableName: "Wow.exe",
        supportsVanillaTweaks: false,
        supportsDLLLoading: false,
        usesRosettaPatching: false,
        settings: VersionSettings(
            autoDeleteWdb: false,
            enableLibSiliconPatch: false,
            x87Backend: .disabled,
            portal: "wow.ulk.me:1119"
        )
    )

    static let genericD3D9Template = GameVersion(
        id: genericD3D9TemplateID,
        displayName: "Non-WoW game (32-bit D3D9)",
        profileKind: .genericD3D9,
        wowVersion: "",
        executableName: "Game.exe",
        supportsVanillaTweaks: false,
        supportsDLLLoading: false,
        usesRosettaPatching: false,
        settings: VersionSettings(autoDeleteWdb: false)
    )

    static var profileTemplates: [String: GameVersion] {
        var templates = defaultVersions
        templates[genericD3D9TemplateID] = genericD3D9Template
        templates[bfa837X64TemplateID] = bfa837X64Template
        return templates
    }

    static func makeDefault() -> VersionManager {
        VersionManager(
            currentVersionID: defaultCurrentVersionID,
            versions: defaultVersions
        )
    }

    var currentVersion: GameVersion? {
        versions[currentVersionID]
    }

    mutating func ensureDefaults() {
        for (id, defaultVersion) in VersionManager.defaultVersions {
            if var existing = versions[id] {
                existing.syncCapabilities(with: defaultVersion)
                existing.settings = existing.settings.mergedWithDefaults(defaultVersion.settings)
                versions[id] = existing
            } else {
                versions[id] = defaultVersion
            }
        }

        versions.removeValue(forKey: "epochsilicon")
        versions.removeValue(forKey: "turtlesilicon")

        if versions[currentVersionID] == nil {
            currentVersionID = VersionManager.defaultCurrentVersionID
        }
    }

    func orderedVersions() -> [GameVersion] {
        var ordered: [GameVersion] = []
        var seen = Set<String>()

        for identifier in VersionManager.defaultOrder {
            if let version = versions[identifier] {
                ordered.append(version)
                seen.insert(identifier)
            }
        }

        for (key, value) in versions where !seen.contains(key) {
            ordered.append(value)
        }

        return ordered
    }

    mutating func updateCurrentVersion(_ update: (inout GameVersion) -> Void) {
        guard var version = versions[currentVersionID] else { return }
        update(&version)
        versions[currentVersionID] = version
    }

    mutating func setCurrentVersion(id: String) {
        guard versions[id] != nil else { return }
        currentVersionID = id
    }
}
