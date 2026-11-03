import Foundation

/// A known way for an integrated Wine launch to die, with the message shown to the user.
enum WineLaunchFailure: Equatable, Sendable {
    case prefixNot64Bit
    case vulkanUnavailable
    case executableNotFound
    case tlsLibraryMissing
    case clientCrashed
    case unhandledException
    case exitedAtStartup(code: Int32)

    func userMessage(logPath: String?) -> String {
        let logLine = logPath.map { "\n\nFull output: \($0)" } ?? ""
        switch self {
        case .prefixNot64Bit:
            return "Wine could not start because the Wine prefix cannot run 64-bit programs (kernel32 failed to load). Choose another Wine bottle in Options or recreate this one with the bundled Wine runtime." + logLine
        case .vulkanUnavailable:
            return "The game could not create a Vulkan instance, so the graphics driver is unavailable. Check the Vulkan driver in Graphics settings (MoltenVK is the safe choice) and that the Wine runtime is complete." + logLine
        case .executableNotFound:
            return "Wine could not find the game executable. Check the game path and executable name of this profile." + logLine
        case .tlsLibraryMissing:
            return "The bundled Wine runtime cannot load GnuTLS (libgnutls), so secure connections and the Battle.net login do not work (BLZ51901015) and the client may crash. The runtime's external libraries are not linked into lib/wine/x86_64-unix: reinstall or rebuild the Wine runtime (tools/wine-runtime/validate.sh detects this)." + logLine
        case .clientCrashed:
            return "The game client crashed (ERROR #132, fatal exception). A crash report was written to the Errors folder inside the game folder." + logLine
        case .unhandledException:
            return "The game crashed with an unhandled exception." + logLine
        case .exitedAtStartup(let code):
            return "The game stopped at startup (exit code \(code))." + logLine
        }
    }
}

enum WineOutputClassifier {
    /// A run that fails faster than this without a known cause is reported as a startup failure.
    static let startupWindow: TimeInterval = 10

    /// Lines Wine prints when it cannot load GnuTLS, whatever the exit code that follows.
    static let tlsMarkers = ["Failed to load libgnutls", "no schannel support"]

    static func indicatesMissingTLS(_ text: String) -> Bool {
        tlsMarkers.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// Returns nil for a normal exit and for a non-zero exit after a long session with no known cause.
    /// A clean exit (code 0) is still reported when GnuTLS was missing or the client crashed
    /// (ERROR #132): the client can close itself after either. A death by signal (`bySignal`, `exitCode` is the signal number) is only
    /// reported for a known cause, since a user force-quitting Wine also ends that way.
    static func classify(
        exitCode: Int32,
        duration: TimeInterval,
        outputTail: String,
        bySignal: Bool = false
    ) -> WineLaunchFailure? {
        if exitCode == 0, !bySignal {
            if indicatesMissingTLS(outputTail) { return .tlsLibraryMissing }
            // The WoW crash handler can let the process end with code 0 after ERROR #132.
            let crashed = ["ERROR #132", "Fatal exception!"].contains {
                outputTail.range(of: $0, options: .caseInsensitive) != nil
            }
            return crashed ? .clientCrashed : nil
        }

        let text = outputTail
        func has(_ needles: String...) -> Bool {
            needles.contains { text.range(of: $0, options: .caseInsensitive) != nil }
        }

        if has("wine: cannot find") { return .executableNotFound }
        if has("could not load kernel32", "WINEARCH set to win64 but", "is not a 64-bit prefix", "cannot be used for 64-bit") {
            return .prefixNot64Bit
        }
        if has("vkCreateInstance", "Failed to create Vulkan instance", "VK_ERROR_INCOMPATIBLE_DRIVER", "VK_ERROR_INITIALIZATION_FAILED") {
            return .vulkanUnavailable
        }
        // Root cause first: without GnuTLS the login fails or the client dies right after.
        // The FreeType warning ("Wine cannot find the FreeType font library") is deliberately not
        // matched: Wine on macOS falls back to CoreText fonts and prints it on healthy runs too.
        if indicatesMissingTLS(text) { return .tlsLibraryMissing }
        // The WoW client's own crash handler (before Wine's generic unhandled exception).
        if has("ERROR #132", "Fatal exception!") { return .clientCrashed }
        if has("Unhandled exception", "page fault on") { return .unhandledException }

        if !bySignal, duration < startupWindow { return .exitedAtStartup(code: exitCode) }
        return nil
    }
}

/// Spots the GnuTLS failure line as the output streams in, independently of the bounded tail
/// (which can drop a line written at startup). Reports it once per launch, even if it comes back
/// and even if a marker is split between two chunks.
final class TLSFailureWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var carry = ""
    private var fired = false
    private let carryLength = (WineOutputClassifier.tlsMarkers.map(\.count).max() ?? 0) - 1

    /// True only the first time a marker is seen.
    func consume(_ chunk: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return false }
        let window = carry + chunk
        if WineOutputClassifier.indicatesMissingTLS(window) {
            fired = true
            carry = ""
            return true
        }
        carry = String(window.suffix(max(carryLength, 0)))
        return false
    }

    var hasFired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fired
    }
}

/// Keeps the last `maxLines` lines (and at most `maxBytes` of text) of a process output stream.
struct BoundedOutputTail: Sendable {
    let maxLines: Int
    let maxBytes: Int
    private let maxLineLength = 4096
    private(set) var lines: [String] = []
    private var partial = ""
    private var byteCount = 0

    init(maxLines: Int = 50, maxBytes: Int = 64 * 1024) {
        self.maxLines = maxLines
        self.maxBytes = maxBytes
    }

    mutating func append(_ chunk: String) {
        partial += chunk
        while let newline = partial.firstIndex(of: "\n") {
            push(String(partial[partial.startIndex..<newline]))
            partial = String(partial[partial.index(after: newline)...])
        }
        if partial.count > maxLineLength {
            push(String(partial.prefix(maxLineLength)))
            partial = ""
        }
    }

    var text: String {
        (partial.isEmpty ? lines : lines + [partial]).joined(separator: "\n")
    }

    private mutating func push(_ line: String) {
        let clipped = String(line.prefix(maxLineLength))
        lines.append(clipped)
        byteCount += clipped.utf8.count + 1
        while lines.count > maxLines || (byteCount > maxBytes && lines.count > 1) {
            byteCount -= lines.removeFirst().utf8.count + 1
        }
    }
}

/// Collects a Wine process output: a bounded tail in memory for classification, the full stream in a log file.
final class WineOutputCapture: @unchecked Sendable {
    static let maxLogBytes = 20 * 1024 * 1024

    let logURL: URL?
    private let lock = NSLock()
    private var tail = BoundedOutputTail()
    private var handle: FileHandle?
    private var written = 0

    init(logURL: URL?) {
        if let logURL {
            let fm = FileManager.default
            try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.createFile(atPath: logURL.path, contents: nil) {
                handle = try? FileHandle(forWritingTo: logURL)
            }
        }
        self.logURL = handle == nil ? nil : logURL
    }

    func append(_ data: Data, stream: String) {
        guard !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        defer { lock.unlock() }
        tail.append(text)
        if let handle, written < Self.maxLogBytes {
            written += data.count
            try? handle.write(contentsOf: data)
            if written >= Self.maxLogBytes {
                try? handle.write(contentsOf: Data("\n[log truncated at \(Self.maxLogBytes) bytes]\n".utf8))
            }
        }
    }

    var tailText: String {
        lock.lock()
        defer { lock.unlock() }
        return tail.text
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }

    static func defaultLogURL(profileID: String, now: Date = Date()) -> URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeID = String(profileID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.prefix(40))
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(AppIdentityMigration.currentSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("launch-\(safeID)-\(formatter.string(from: now)).log", isDirectory: false)
    }
}
