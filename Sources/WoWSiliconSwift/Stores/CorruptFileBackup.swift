import Foundation

/// Sets aside a JSON file that no longer decodes, so a later save can never overwrite it.
enum CorruptFileBackup {
    /// Renames `url` to `<name>.corrupt-<yyyyMMdd-HHmmss>` (a numeric suffix is added when that name is taken).
    /// Falls back to a copy when the rename fails. Returns nil when neither works: callers must then
    /// refuse to write the original path.
    static func preserve(
        _ url: URL,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)
        let base = url.lastPathComponent + ".corrupt-" + stamp

        var target = url.deletingLastPathComponent().appendingPathComponent(base)
        var counter = 1
        while fileManager.fileExists(atPath: target.path) {
            target = url.deletingLastPathComponent().appendingPathComponent("\(base)-\(counter)")
            counter += 1
        }

        if (try? fileManager.moveItem(at: url, to: target)) != nil {
            return target
        }
        if (try? fileManager.copyItem(at: url, to: target)) != nil {
            return target
        }
        return nil
    }
}
