# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
swift build                                  # debug build, no Wine runtime needed
swift test                                   # full XCTest suite (also what CI runs)
swift test --filter GameLaunchCoordinatorTests   # single test class
swift test --filter GameLaunchCoordinatorTests/testName   # single test
make bundle                                  # release build + WoWSilicon.app in .build/
make run                                     # bundle, then open the app
make dmg                                     # DMG in .build/release-archives/
make xcode                                   # open WoWSilicon.xcodeproj
xcodebuild -scheme WoWSilicon -configuration Debug CODE_SIGNING_ALLOWED=NO test   # Xcode tests from the CLI
```

- `make bundle` requires the Wine runtime at `.wine-runtime/` (override with `WINE_RUNTIME_DIR`). Restore it with `tools/wine-runtime/restore.sh --runtime .wine-runtime`, or validate with `make validate_wine_runtime`.
- `make bundle` also builds `tools/wine-audio-helper/wowsilicon-audio.c` with `i686-w64-mingw32-gcc` (`brew install mingw-w64`).
- The Makefile builds with `--arch arm64 --sdk ... --disable-sandbox` and custom build paths. Use `make build` or `make debug` rather than bare `swift build -c release`.

## Architecture

**Two build entry points, one source tree.** `WoWSilicon.xcodeproj` (hand-written, no Tuist) and `Package.swift` (SPM, used by `swift build`/`swift test`) both build `Sources/WoWSiliconSwift`. The Xcode project uses synchronized folder groups, so new files under `Sources/` or `Tests/WoWSiliconSwiftTests` are picked up without editing the project. `Resources/Patching/` is the exception: it is a folder reference that keeps its subfolders, because several files share names across them (`LICENSE`, `d3d9.dll`, `libSiliconPatch.dll`). Its files are excluded from the synchronized group; new files added there still get copied automatically. Version numbers live in `WoWSilicon.xcodeproj` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) and `Packaging/Info.plist`; `tools/release/set_version.sh` syncs them during release. Sparkle is a remote SPM package in the Xcode project; it is embedded automatically, with no Embed phase.

**Xcode build phases.** `Bundle Wine runtime` runs `tools/xcode/bundle-wine-runtime.sh` on every build (`alwaysOutOfDate`): it copies `.wine-runtime/` and the audio helper into the bundle, like `make bundle`. A Release build without `.wine-runtime/` fails; Debug only warns.

**Layers** (under `Sources/WoWSiliconSwift/`):
- `Models/` holds the data. `GameVersion` is a launcher "profile" (one game folder plus its `GraphicsSettings` and `VersionSettings`). `VersionManager` wraps the profile list. `GameProfileKind` distinguishes WoW client families from `generic_d3d9` profiles.
- `Stores/` persists state: `VersionStore` (profiles on disk), `UserPrefsStore`.
- `Services/` does the work, and most of it shells out to Wine. `ProcessRunner` runs child processes, `WineBottleService` creates and manages the Wine prefix, `LaunchService` starts a client, `PatchService` and `PatchingStatusChecker` manage game-folder patching, `ConfigService` and `DXVKConfigService` write per-profile config, `AddonService` and `ModService` manage addons and DLL mods, `UpdaterService` wraps Sparkle, and `TelemetryService` reports to the Cloudflare Worker in `tools/telemetry-worker/`.
- `ViewModels/` sits between Views and Services. `MainDashboardViewModel` is the root state. `GameLaunchCoordinator` runs launch preflight (`GameLaunchPreflight`) and then the launch.
- `Views/` is SwiftUI only. `WoWSiliconSwiftApp.swift` sets up the single `Window`, the Sparkle menu command, and the `AppDelegate`.

**Bundled runtime.** The app ships its own Wine and patch DLLs; it never relies on a system Wine.
1. `tools/wine-runtime/build.sh` and `fetch-source.sh` build the runtime outside this repo. `assemble.sh` and `package.sh` produce `.wine-runtime/`.
2. `Packaging/WineRuntime/` holds the pinned versions: `runtime-lock.json`, `artifact-lock.json`, and the `patches/` applied to Wine. `Packaging/X87Sidecar/x87sidecar-lock.json` pins the x87 helper. `make update-mtld3d` and `make update-x87sidecar` bump those locks.
3. `make bundle` copies `.wine-runtime/` to `Contents/Resources/Wine/`. At runtime, `BundledWineRuntime` resolves that path from `Bundle.main`.
4. Patch DLLs and helpers under `Resources/Patching/` (d9vk, rosettax87, libSiliconPatch, vanilla-tweaks, x87sidecar, winerosetta, and per-client folders `vanilla/`, `wotlk/`) are copied into the game folder by `PatchService`. `BundledRosettaRuntime` resolves the x87 helper paths.

**Test client.** `wow-silo-client/` is the team's 3.3.5 (frFR) client used for manual end-to-end tests. Point a WotLK profile at it. It is git-ignored: it holds Blizzard data (19 GB, files over GitHub's 100 MB limit), and its WoWSilicon files (`mods/`, `d3d9.dll`, `libDllLdr.dll`, `dlls.txt`, `mtld3d.conf`) are written by `PatchService` from `Resources/Patching/`. Never edit them there; edit the sources and re-patch.

**Wine is called as a subprocess.** Everything that touches Wine goes through `ProcessRunner`. Wine-specific logic (registry edits, focus matching, process monitoring) lives in `WineRegistrySupport`, `WineApplicationFocusMatcher`, and `WineProcessMonitor`. Changes there need a Mac with the bundled runtime to test end to end. Unit tests can only cover the Swift side.

**Release flow.** Pushing a `v*.*.*` tag triggers `.github/workflows/release.yml` (macos-26). It restores the Wine runtime, sets the version from the tag, and runs `make dmg` and `make appcast`. The appcast is published to the Pages repo. Release notes go in `docs/releases/<version>.md`. Secrets are described in `docs/releasing.md`.

## Rules

- **Never write to the upstream repository `https://github.com/WoWSilicon/WoWSilicon`.** No commit, push, tag, branch, issue, comment, PR, label or setting change, whether through `git`, `gh`, the GitHub API or an MCP tool. It is not this project's repository. The only repository to write to is `izo/WoWSilicon-silo` (`origin`).
- **Name the target explicitly.** Run `git remote get-url origin` before any push, and always pass `--repo izo/WoWSilicon-silo` to `gh`. `gh` has no default repository set here and can resolve to the upstream one.
- If a task seems to need a change upstream, stop and tell the user. Reading upstream (`gh issue view`, `gh repo view`) is fine.

## Conventions

- Keep Swift 6 strict concurrency clean (`swift-tools-version: 6.0`, `SWIFT_VERSION` 6.0). `GameVersion` and friends are `Sendable` value types. Most services are `enum` namespaces or `struct`s. `LaunchService` and `TelemetryService` are `final class`es.
