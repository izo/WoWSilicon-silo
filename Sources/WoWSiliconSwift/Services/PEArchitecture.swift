import Foundation

/// Reads the machine type from a Windows PE header. Pure and crash-free on malformed input.
enum PEArchitecture: Equatable, Sendable {
    case x86
    case x86_64
    case unknown

    static let machineX86: UInt16 = 0x014C
    static let machineX86_64: UInt16 = 0x8664

    /// Parses a PE image prefix. Needs `e_lfanew` (0x3C) and the 6 bytes at the PE header.
    static func parse(_ data: Data) -> PEArchitecture {
        let bytes = [UInt8](data)
        guard bytes.count >= 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A else { return .unknown }
        let offset = Int(bytes[0x3C])
            | Int(bytes[0x3D]) << 8
            | Int(bytes[0x3E]) << 16
            | Int(bytes[0x3F]) << 24
        guard offset >= 0, offset <= bytes.count - 6 else { return .unknown }
        guard bytes[offset] == 0x50, bytes[offset + 1] == 0x45,
              bytes[offset + 2] == 0, bytes[offset + 3] == 0 else { return .unknown }
        let machine = UInt16(bytes[offset + 4]) | UInt16(bytes[offset + 5]) << 8
        switch machine {
        case machineX86: return .x86
        case machineX86_64: return .x86_64
        default: return .unknown
        }
    }

    /// Reads only the first 64 KiB of the file, which covers the PE header of any real executable.
    static func read(from url: URL) -> PEArchitecture {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024) else { return .unknown }
        return parse(data)
    }

    /// Returns a user-facing warning when `architecture` does not match the profile family.
    static func mismatchMessage(for architecture: PEArchitecture, profileKind: GameProfileKind) -> String? {
        switch (architecture, profileKind) {
        case (.x86_64, .worldOfWarcraft), (.x86_64, .genericD3D9):
            return "This executable is 64-bit (x86-64). This profile is for 32-bit clients. "
                + "Create a profile based on \"Battle for Azeroth 8.3.7 (x64)\" instead."
        case (.x86, .worldOfWarcraftX64):
            return "This executable is 32-bit (x86). The x64 profile is for 64-bit clients. "
                + "Create a profile based on a 32-bit model (WoW 1.12 / 2.4.3 / 3.3.5 or Non-WoW game) instead."
        default:
            return nil
        }
    }
}
