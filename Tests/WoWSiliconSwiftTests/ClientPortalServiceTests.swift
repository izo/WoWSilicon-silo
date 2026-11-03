import XCTest
@testable import WoWSiliconSwift

final class ClientPortalServiceTests: XCTestCase {
    func testReplacesExistingPortalLineAndKeepsTheRest() {
        let content = "SET portal \"US\"\nSET textLocale \"frFR\"\n"
        XCTAssertEqual(
            ClientPortalService.updatedContent(content, portal: "wow.ulk.me:1119"),
            "SET portal \"wow.ulk.me:1119\"\nSET textLocale \"frFR\"\n"
        )
    }

    func testAddsPortalWhenMissingAndOnEmptyFile() {
        XCTAssertEqual(
            ClientPortalService.updatedContent("SET gxApi \"D3D12\"\n", portal: "a.b:1119"),
            "SET portal \"a.b:1119\"\nSET gxApi \"D3D12\"\n"
        )
        XCTAssertEqual(ClientPortalService.updatedContent("", portal: "a.b"), "SET portal \"a.b\"\n")
    }

    func testRefusesPortalsThatCouldInjectLines() {
        XCTAssertTrue(ClientPortalService.isValidPortal("wow.ulk.me:1119"))
        XCTAssertFalse(ClientPortalService.isValidPortal("a.b\"\nSET x \"1"))
        XCTAssertFalse(ClientPortalService.isValidPortal("a b"))
        XCTAssertFalse(ClientPortalService.isValidPortal(""))
    }

    func testApplyWritesConfigAndIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ClientPortalService.apply(portal: "wow.ulk.me:1119", gameURL: dir)
        try ClientPortalService.apply(portal: "wow.ulk.me:1119", gameURL: dir)
        let text = try String(contentsOf: dir.appendingPathComponent("WTF/Config.wtf"), encoding: .utf8)
        XCTAssertEqual(text, "SET portal \"wow.ulk.me:1119\"\n")
    }

    func testSettingsWithoutPortalKeyDecodeToEmpty() throws {
        let settings = try JSONDecoder().decode(VersionSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.portal, "")
        let roundTrip = try JSONDecoder().decode(VersionSettings.self, from: JSONEncoder().encode(VersionSettings(portal: "h:1")))
        XCTAssertEqual(roundTrip.portal, "h:1")
    }
}
