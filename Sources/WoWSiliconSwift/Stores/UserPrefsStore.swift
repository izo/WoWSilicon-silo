import Foundation

struct UserPrefsStore {
    private let fileManager: FileManager
    private let supportDirectory: URL?
    private let directoryName = AppIdentityMigration.currentSupportDirectoryName
    private let fileName = "prefs.json"

    init(fileManager: FileManager = .default, supportDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.supportDirectory = supportDirectory
    }

    struct LoadResult {
        var prefs: UserPrefs
        /// Where the unreadable `prefs.json` was set aside, when decoding failed.
        var corruptBackupURL: URL?
    }

    func load() -> UserPrefs {
        loadWithReport().prefs
    }

    func loadWithReport() -> LoadResult {
        guard let prefsURL = prefsFileURL(),
              fileManager.fileExists(atPath: prefsURL.path) else {
            return LoadResult(prefs: .defaults)
        }

        do {
            let data = try Data(contentsOf: prefsURL)
            let prefs = try JSONDecoder().decode(UserPrefs.self, from: data)
            return LoadResult(prefs: prefs)
        } catch {
            debugPrint("Failed to load prefs.json: \(error.localizedDescription)")
            // Set the file aside so the next save cannot overwrite it with defaults.
            let backup = CorruptFileBackup.preserve(prefsURL, fileManager: fileManager)
            return LoadResult(prefs: .defaults, corruptBackupURL: backup)
        }
    }

    func save(_ prefs: UserPrefs) {
        guard let prefsURL = prefsFileURL() else {
            debugPrint("Unable to resolve prefs.json path")
            return
        }

        let directoryURL = prefsURL.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(prefs)
            if (try? Data(contentsOf: prefsURL)) == data {
                return
            }
            try data.write(to: prefsURL, options: .atomic)
        } catch {
            debugPrint("Failed to save prefs.json: \(error.localizedDescription)")
        }
    }

    private func prefsFileURL() -> URL? {
        guard let supportDirectory = supportDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
