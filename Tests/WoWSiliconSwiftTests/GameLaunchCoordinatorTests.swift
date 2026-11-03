import XCTest
@testable import WoWSiliconSwift

@MainActor
final class GameLaunchCoordinatorTests: XCTestCase {
    func testExistingWineIsDeferredUntilUserDecision() async throws {
        let version = try XCTUnwrap(VersionManager.defaultVersions[VersionManager.defaultCurrentVersionID])
        let coordinator = GameLaunchCoordinator(
            processCountProvider: { 2 },
            gameLauncher: { _ in XCTFail("Preflight must not launch while Wine is running") }
        )

        let result = await coordinator.prepareLaunch(version: version, isAudioBusy: { false })
        guard case .existingWine(let processCount) = result else {
            return XCTFail("Expected an existing Wine result")
        }
        XCTAssertEqual(processCount, 2)

        let pending = try XCTUnwrap(coordinator.resolvePendingLaunch(cleanUp: true))
        XCTAssertEqual(pending.version, version)
        XCTAssertTrue(pending.shouldCleanUpWine)
        XCTAssertNil(coordinator.resolvePendingLaunch(cleanUp: false))
    }

    func testReadyPreflightAndSuccessfulLaunch() async throws {
        let version = try XCTUnwrap(VersionManager.defaultVersions[VersionManager.defaultCurrentVersionID])
        let launches = LaunchCounter()
        let coordinator = GameLaunchCoordinator(
            processCountProvider: { 0 },
            gameLauncher: { _ in await launches.increment() }
        )

        let preflight = await coordinator.prepareLaunch(version: version, isAudioBusy: { false })
        guard case .ready(let processCount) = preflight else {
            return XCTFail("Expected launch to be ready")
        }
        XCTAssertEqual(processCount, 0)

        let outcome = await coordinator.launchPrepared(version)
        guard case .started = outcome else {
            return XCTFail("Expected a successful launch")
        }
        let launchCount = await launches.value()
        XCTAssertEqual(launchCount, 1)
    }

    private func x64Version(portal: String) -> GameVersion {
        var version = GameVersion(
            id: "x64", displayName: "BfA", profileKind: .worldOfWarcraftX64, wowVersion: "8.3.7",
            gamePath: "/tmp/x64", executableName: "Wow.exe",
            supportsVanillaTweaks: false, supportsDLLLoading: false, usesRosettaPatching: false
        )
        version.settings.portal = portal
        return version
    }

    func testInvalidPortalBlocksLaunchBeforeAnythingStarts() async {
        let coordinator = GameLaunchCoordinator(
            processCountProvider: { XCTFail("Must not look at Wine processes"); return 0 },
            gameLauncher: { _ in XCTFail("Must not launch with an invalid portal") }
        )
        let result = await coordinator.prepareLaunch(version: x64Version(portal: "US portal"), isAudioBusy: { false })
        guard case .blocked(let error) = result, case .invalidPortal(let portal) = error else {
            return XCTFail("Expected a blocked preflight")
        }
        XCTAssertEqual(portal, "US portal")
        let message = error.localizedDescription
        XCTAssertTrue(message.contains(ClientConfigWTFService.portalFormatHint))
    }

    func testEmptyOrValidPortalDoesNotBlock() async {
        let coordinator = GameLaunchCoordinator(processCountProvider: { 0 }, gameLauncher: { _ in })
        for portal in ["", "  ", "wow.ulk.me:1119", " wow.ulk.me "] {
            let result = await coordinator.prepareLaunch(version: x64Version(portal: portal), isAudioBusy: { false })
            guard case .ready = result else { return XCTFail("Portal \"\(portal)\" must not block") }
        }
    }

    func testPortalIsIgnoredForNonX64Profiles() throws {
        var version = try XCTUnwrap(VersionManager.defaultVersions[VersionManager.defaultCurrentVersionID])
        version.settings.portal = "not valid"
        XCTAssertNil(ClientConfigWTFService.invalidPortal(for: version))
    }

    func testLaunchErrorsBecomePresentationOutcomes() async throws {
        let version = try XCTUnwrap(VersionManager.defaultVersions[VersionManager.defaultCurrentVersionID])
        let coordinator = GameLaunchCoordinator(
            gameLauncher: { _ in throw LaunchServiceError.versionMismatch("base", "tweaked") }
        )

        let outcome = await coordinator.launchPrepared(version)
        guard case .versionMismatch(let base, let tweaked) = outcome else {
            return XCTFail("Expected a version mismatch outcome")
        }
        XCTAssertEqual(base, "base")
        XCTAssertEqual(tweaked, "tweaked")
    }
}

private actor LaunchCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
