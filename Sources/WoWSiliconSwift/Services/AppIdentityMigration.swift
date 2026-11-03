import Foundation

/// One-time carry-over of user state from the former app identity
/// (`WoWSilicon`, bundle id `com.wowsilicon.swift`) to the current one
/// (`SiloWow`, bundle id `silowow.regrets.app`). Nothing is ever moved or deleted
/// from the legacy locations: the upstream app keeps working untouched.
enum AppIdentityMigration {
    static let currentSupportDirectoryName = "SiloWow"
    static let legacySupportDirectoryName = "WoWSilicon"
    static let legacyDefaultsDomain = "com.wowsilicon.swift"
    static let defaultsMigrationFlag = "silowow.defaultsMigratedFromLegacyDomain"

    /// Keys worth carrying over: Sparkle preferences (`SU…`) and the launcher's own UI choices.
    static func isMigratedDefaultsKey(_ key: String) -> Bool {
        key.hasPrefix("SU") || key == "realmlistEditorMode"
    }

    /// Copies `Application Support/WoWSilicon` to `Application Support/SiloWow` when the latter
    /// does not exist yet. Returns true when a copy was made.
    @discardableResult
    static func copyLegacySupportDirectoryIfNeeded(
        supportURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let support = supportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        let current = support.appendingPathComponent(currentSupportDirectoryName, isDirectory: true)
        let legacy = support.appendingPathComponent(legacySupportDirectoryName, isDirectory: true)
        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path) else {
            return false
        }
        do {
            try fileManager.copyItem(at: legacy, to: current)
            return true
        } catch {
            debugPrint("Failed to copy legacy support directory: \(error.localizedDescription)")
            try? fileManager.removeItem(at: current)
            return false
        }
    }

    /// Copies Sparkle and UI preferences from the legacy defaults domain, once. Values already set
    /// in the current domain win. Returns the number of keys copied.
    @discardableResult
    static func migrateLegacyDefaultsIfNeeded(
        current: UserDefaults = .standard,
        legacyDomain: String = legacyDefaultsDomain,
        legacyValues: [String: Any]? = nil
    ) -> Int {
        guard !current.bool(forKey: defaultsMigrationFlag) else { return 0 }
        let legacy = legacyValues
            ?? UserDefaults(suiteName: legacyDomain)?.persistentDomain(forName: legacyDomain)
            ?? [:]
        var copied = 0
        for (key, value) in legacy where isMigratedDefaultsKey(key) {
            guard current.object(forKey: key) == nil else { continue }
            current.set(value, forKey: key)
            copied += 1
        }
        current.set(true, forKey: defaultsMigrationFlag)
        return copied
    }
}
