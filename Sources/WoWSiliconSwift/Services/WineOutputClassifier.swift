import Foundation

/// A known way for an integrated Wine launch to die, with the message shown to the user.
enum WineLaunchFailure: Equatable, Sendable {
    case prefixNot64Bit
    case vulkanUnavailable
    case executableNotFound
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

    /// Returns nil for a normal exit and for a non-zero exit after a long session with no known cause.
    static func classify(
        exitCode: Int32,
        duration: TimeInterval,
        outputTail: String
    ) -> WineLaunchFailure? {
        guard exitCode != 0 else { return nil }

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
        if has("Unhandled exception", "page fault on") { return .unhandledException }

        if duration < startupWindow { return .exitedAtStartup(code: exitCode) }
        return nil
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
