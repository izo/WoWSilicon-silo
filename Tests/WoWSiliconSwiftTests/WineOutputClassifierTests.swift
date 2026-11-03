import XCTest
@testable import WoWSiliconSwift

final class WineOutputClassifierTests: XCTestCase {
    func testNormalExitAfterLongSessionShowsNothing() {
        let noisy = "fixme:ntdll:NtQuerySystemInformation stub\nerr:vulkan:something harmless"
        XCTAssertNil(WineOutputClassifier.classify(exitCode: 0, duration: 3600, outputTail: noisy))
        XCTAssertNil(WineOutputClassifier.classify(exitCode: 0, duration: 2, outputTail: ""))
        XCTAssertNil(WineOutputClassifier.classify(exitCode: 1, duration: 3600, outputTail: noisy))
    }

    func testNonZeroExitAtStartupWithoutKnownCause() {
        XCTAssertEqual(
            WineOutputClassifier.classify(exitCode: 3, duration: 2.5, outputTail: "fixme:foo"),
            .exitedAtStartup(code: 3)
        )
    }

    func testPrefixNot64Bit() {
        let out = """
        wine: created the configuration directory '/Users/x/Wine'
        0024:err:module:import_dll Library KERNEL32.dll not found
        wine: could not load kernel32.dll, status c0000135
        """
        XCTAssertEqual(WineOutputClassifier.classify(exitCode: 1, duration: 1, outputTail: out), .prefixNot64Bit)
    }

    func testVulkanUnavailable() {
        let out = "err:winevulkan:wine_vk_init vkCreateInstance failed, VK_ERROR_INCOMPATIBLE_DRIVER\nFailed to create Vulkan instance."
        XCTAssertEqual(WineOutputClassifier.classify(exitCode: 1, duration: 4, outputTail: out), .vulkanUnavailable)
    }

    func testExecutableNotFound() {
        let out = "wine: cannot find 'Z:\\\\Games\\\\WoW\\\\WoW.exe'"
        XCTAssertEqual(WineOutputClassifier.classify(exitCode: 1, duration: 0.3, outputTail: out), .executableNotFound)
    }

    func testUnhandledExceptionEvenAfterLongSession() {
        let out = "wine: Unhandled exception 0xc0000005 in thread 9f at address 000000014012ab34"
        XCTAssertEqual(WineOutputClassifier.classify(exitCode: 1, duration: 900, outputTail: out), .unhandledException)
        let pf = "wine: Unhandled page fault on read access to 0000000000000010 at address 0000000140001234"
        XCTAssertEqual(WineOutputClassifier.classify(exitCode: 1, duration: 900, outputTail: pf), .unhandledException)
    }

    func testMessagesCarryLogPath() {
        let path = "/Users/x/Library/Logs/SiloWow/launch-a.log"
        let failures: [WineLaunchFailure] = [
            .prefixNot64Bit, .vulkanUnavailable, .executableNotFound, .unhandledException, .exitedAtStartup(code: 1)
        ]
        for failure in failures {
            XCTAssertTrue(failure.userMessage(logPath: path).contains(path))
        }
        XCTAssertTrue(WineLaunchFailure.exitedAtStartup(code: 1).userMessage(logPath: path).contains("stopped at startup"))
    }

    func testTailIsBoundedByLinesAndBytes() {
        var tail = BoundedOutputTail(maxLines: 50, maxBytes: 64 * 1024)
        for i in 0..<10_000 { tail.append("line \(i)\n") }
        XCTAssertEqual(tail.lines.count, 50)
        XCTAssertEqual(tail.lines.last, "line 9999")
        XCTAssertEqual(tail.lines.first, "line 9950")

        var bytes = BoundedOutputTail(maxLines: 50, maxBytes: 1000)
        for _ in 0..<40 { bytes.append(String(repeating: "x", count: 200) + "\n") }
        XCTAssertLessThanOrEqual(bytes.text.utf8.count, 1000 + 200)

        var huge = BoundedOutputTail()
        huge.append(String(repeating: "y", count: 1_000_000))
        XCTAssertLessThanOrEqual(huge.text.utf8.count, 4096 + 4096)
    }

    func testTailHandlesChunksSplitMidLine() {
        var tail = BoundedOutputTail()
        tail.append("wine: cann")
        tail.append("ot find 'x'\nnext")
        XCTAssertEqual(tail.lines, ["wine: cannot find 'x'"])
        XCTAssertTrue(tail.text.hasSuffix("next"))
    }

    func testCaptureWritesFullLogButKeepsBoundedTail() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-\(UUID().uuidString)/launch.log")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let capture = WineOutputCapture(logURL: url)
        for i in 0..<500 { capture.append(Data("line \(i)\n".utf8), stream: "stderr") }
        capture.close()

        XCTAssertEqual(capture.logURL, url)
        let full = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(full.contains("line 0\n"))
        XCTAssertTrue(full.contains("line 499\n"))
        XCTAssertFalse(capture.tailText.contains("line 0\n"))
        XCTAssertTrue(capture.tailText.contains("line 499"))
    }
}
