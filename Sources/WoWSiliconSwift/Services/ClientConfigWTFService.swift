import Foundation

/// Writes `SET <key> "<value>"` lines in an 8.x client's `WTF/Config.wtf` without touching the other lines.
/// Every value is validated against a closed format, so a profile can never inject extra lines.
enum ClientConfigWTFService {
    /// Config.wtf could not be read or written without risking the other keys.
    enum ConfigError: LocalizedError {
        case unreadable(path: String, reason: String)
        case notEncodable(path: String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let path, let reason):
                return "Could not read the client's Config.wtf at \(path), so it was left untouched. \(reason)"
            case .notEncodable(let path):
                return "Config.wtf at \(path) was left untouched: the new settings cannot be saved in its text encoding."
            }
        }
    }

    /// Graphics API forced for x64 profiles: the launch already passes `-d3d11`, and a client
    /// that wrote `D3D12` itself would otherwise disagree with it.
    static let forcedGxApi = "D3D11"

    /// Locale codes the 8.x client accepts for `textLocale` and `audioLocale`.
    static let supportedLocales = [
        "enUS", "enGB", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"
    ]

    /// Expected format, shown next to the field and when a launch is blocked.
    static let portalFormatHint = "Use a host name with an optional port, for example wow.ulk.me:1119."

    /// The trimmed portal of an x64 profile when it is set but invalid; nil when launching is fine.
    static func invalidPortal(for version: GameVersion) -> String? {
        guard version.isWorldOfWarcraftX64 else { return nil }
        let portal = version.settings.portal.trimmingCharacters(in: .whitespacesAndNewlines)
        return !portal.isEmpty && !isValidPortal(portal) ? portal : nil
    }

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
            // `SET`, spaces or tabs, the key, then a separator: case-insensitive, tab-tolerant.
            let pattern = #"^\s*set\s+"# + NSRegularExpression.escapedPattern(for: entry.key) + #"\s"#
            var found = false
            for index in lines.indices {
                if lines[index].range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
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
        let existing: String
        var encoding = String.Encoding.utf8
        if fileManager.fileExists(atPath: configURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: configURL)
            } catch {
                // Never replace a file we could not read: that would drop every other key.
                throw ConfigError.unreadable(path: configURL.path, reason: error.localizedDescription)
            }
            if let text = String(data: data, encoding: .utf8) {
                existing = text
            } else {
                // Not UTF-8 (a client or editor wrote ANSI text). ISO Latin-1 maps every byte to one
                // character, so decoding never fails and writing back restores the other lines byte for byte.
                guard let text = String(data: data, encoding: .isoLatin1) else {
                    throw ConfigError.unreadable(path: configURL.path, reason: "The text encoding is not supported.")
                }
                existing = text
                encoding = .isoLatin1
            }
        } else {
            existing = ""
        }
        let updated = updatedContent(existing, entries: entries)
        guard updated != existing else { return }
        guard let output = updated.data(using: encoding) else {
            throw ConfigError.notEncodable(path: configURL.path)
        }
        try fileManager.createDirectory(at: wtfURL, withIntermediateDirectories: true)
        try output.write(to: configURL, options: .atomic)
    }

    /// Applies the settings of an x64 profile to the game folder's Config.wtf.
    static func apply(settings: VersionSettings, gameURL: URL, fileManager: FileManager = .default) throws {
        try apply(entries: entries(for: settings), gameURL: gameURL, fileManager: fileManager)
    }
}
