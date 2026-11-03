import Foundation

/// Writes `SET <key> "<value>"` lines in an 8.x client's `WTF/Config.wtf` without touching the other lines.
/// Every value is validated against a closed format, so a profile can never inject extra lines.
enum ClientConfigWTFService {
    /// Graphics API forced for x64 profiles: the launch already passes `-d3d11`, and a client
    /// that wrote `D3D12` itself would otherwise disagree with it.
    static let forcedGxApi = "D3D11"

    /// Locale codes the 8.x client accepts for `textLocale` and `audioLocale`.
    static let supportedLocales = [
        "enUS", "enGB", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"
    ]

    /// Host (letters, digits, `.`, `-`, `_`) with an optional `:port`.
    static func isValidPortal(_ portal: String) -> Bool {
        portal.range(of: #"^[A-Za-z0-9._-]+(:[0-9]{1,5})?$"#, options: .regularExpression) != nil
    }

    static func isValidLocale(_ locale: String) -> Bool {
        supportedLocales.contains(locale)
    }

    /// Keys are letters and digits only; values never contain a quote or a line break.
    static func isSafe(key: String, value: String) -> Bool {
        key.range(of: #"^[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
            && !value.contains(where: { $0 == "\"" || $0.isNewline })
    }

    /// The lines an x64 profile asks for, in file order. Empty or invalid portal/locale values are
    /// left out, which means "do not touch that key".
    static func entries(for settings: VersionSettings) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        let portal = settings.portal.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidPortal(portal) { result.append(("portal", portal)) }
        result.append(("gxApi", forcedGxApi))
        let text = settings.textLocale.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidLocale(text) { result.append(("textLocale", text)) }
        let audio = settings.audioLocale.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidLocale(audio) { result.append(("audioLocale", audio)) }
        return result
    }

    /// Returns `content` with each entry set. A line already holding the key (matched ignoring case)
    /// is replaced in place; missing keys are appended at the end. Other lines are kept untouched.
    /// Entries that are not safe are skipped.
    static func updatedContent(_ content: String, entries: [(key: String, value: String)]) -> String {
        var lines = content.components(separatedBy: "\n")
        // A trailing newline yields a last empty element: keep it last so appends go before it.
        let endsWithNewline = lines.last == ""
        if endsWithNewline { lines.removeLast() }

        for entry in entries where isSafe(key: entry.key, value: entry.value) {
            let line = "SET \(entry.key) \"\(entry.value)\""
            let prefix = "set \(entry.key.lowercased()) "
            var found = false
            for index in lines.indices {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces).lowercased()
                if trimmed.hasPrefix(prefix) {
                    lines[index] = lines[index].hasSuffix("\r") ? line + "\r" : line
                    found = true
                }
            }
            if !found { lines.append(line) }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    static func apply(
        entries: [(key: String, value: String)],
        gameURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !entries.isEmpty else { return }
        let wtfURL = gameURL.appendingPathComponent("WTF", isDirectory: true)
        let configURL = wtfURL.appendingPathComponent("Config.wtf")
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let updated = updatedContent(existing, entries: entries)
        guard updated != existing else { return }
        try fileManager.createDirectory(at: wtfURL, withIntermediateDirectories: true)
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    /// Applies the settings of an x64 profile to the game folder's Config.wtf.
    static func apply(settings: VersionSettings, gameURL: URL, fileManager: FileManager = .default) throws {
        try apply(entries: entries(for: settings), gameURL: gameURL, fileManager: fileManager)
    }
}
