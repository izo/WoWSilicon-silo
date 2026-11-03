import Foundation

/// Points an 8.x client at a private Battle.net server by writing `SET portal` in `WTF/Config.wtf`.
/// Without it the client keeps its default (`US`) and talks to Blizzard's servers.
enum ClientPortalService {
    /// Host (letters, digits, `.`, `-`, `_`) with an optional `:port`. Anything else is refused,
    /// so a profile can never inject extra lines into Config.wtf.
    static func isValidPortal(_ portal: String) -> Bool {
        portal.range(of: #"^[A-Za-z0-9._-]+(:[0-9]{1,5})?$"#, options: .regularExpression) != nil
    }

    /// Returns `content` with a single `SET portal "<portal>"` line. An existing line is replaced
    /// in place, otherwise the line is added at the top. Other lines are kept untouched.
    static func updatedContent(_ content: String, portal: String) -> String {
        let line = "SET portal \"\(portal)\""
        var lines = content.components(separatedBy: "\n")
        let isPortalLine: (String) -> Bool = {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("set portal ")
        }
        if let index = lines.firstIndex(where: isPortalLine) {
            lines[index] = line
            return lines.joined(separator: "\n")
        }
        if content.isEmpty { return line + "\n" }
        return ([line] + lines).joined(separator: "\n")
    }

    static func apply(portal: String, gameURL: URL, fileManager: FileManager = .default) throws {
        let trimmed = portal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidPortal(trimmed) else { return }

        let wtfURL = gameURL.appendingPathComponent("WTF", isDirectory: true)
        let configURL = wtfURL.appendingPathComponent("Config.wtf")
        try fileManager.createDirectory(at: wtfURL, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = updatedContent(existing, portal: trimmed)
        guard updated != existing else { return }
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }
}
