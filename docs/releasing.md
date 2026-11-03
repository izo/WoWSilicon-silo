# Releasing

SiloWow releases are created from version tags such as `v2.6.0`.

## GitHub Setup

The `izo/WoWSilicon-silo` repository needs one Actions secret, `SPARKLE_PRIVATE_KEY`.
The workflow only runs on that repository and publishes with the built-in `GITHUB_TOKEN`
(no personal access token).

`SPARKLE_PRIVATE_KEY` must be the Sparkle private EdDSA key value only. Do not
use the public key, XML, or the full `generate_keys` output. The secret should
look like one base64 string; optional surrounding quotes or a
`SPARKLE_PRIVATE_KEY=` prefix are tolerated.

The key lives in the macOS keychain under the account `silowow.regrets.app.updates`;
its public half is `SUPublicEDKey` in `Packaging/Info.plist`. To export it and set the
secret, then delete the file:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account silowow.regrets.app.updates -x /tmp/sparkle_key
gh secret set SPARKLE_PRIVATE_KEY --repo izo/WoWSilicon-silo < /tmp/sparkle_key
rm -P /tmp/sparkle_key
```

Updates are served from GitHub Pages: in the repository settings, enable Pages with
source "Deploy from a branch", branch `gh-pages`, folder `/ (root)`. The workflow
creates the `gh-pages` branch on the first release. The feed is
`https://izo.github.io/WoWSilicon-silo/appcast.xml`.

## Wine runtime release

`tools/wine-runtime/restore.sh` downloads the runtime pinned in
`Packaging/WineRuntime/artifact-lock.json` from the release `wine-runtime-r17` of
`izo/WoWSilicon-silo` (asset `WoWSilicon-WineRuntime-r17.tar.xz`). Publish that release on
the fork before the first tag. Use `WINE_RUNTIME_REPOSITORY=owner/repo` or `--repository`
to restore from another repository.

## Versioning

The app uses semantic versions for display and a numeric build number for update ordering.

```text
2.5.0  -> 20500
2.5.1  -> 20501
2.5.10 -> 20510
2.6.0  -> 20600
```

The release workflow computes the build number automatically from the tag.

## Local Builds

```sh
make bundle
make dmg
make appcast
```

For a specific version:

```sh
make dmg VERSION=2.6.0 BUILD_NUMBER=20600
```

To include release notes in the appcast locally, add a markdown file under
`docs/releases/` and pass it to `make appcast`:

```sh
RELEASE_NOTES_FILE=docs/releases/2.6.0.md make appcast VERSION=2.6.0 BUILD_NUMBER=20600
```

## Release Flow

Add release notes for the version:

```sh
docs/releases/2.6.0.md
```

Then update the version, commit it, and create and push a tag:

```sh
tools/release/set_version.sh 2.6.0
git add Packaging/Info.plist WoWSilicon.xcodeproj/project.pbxproj docs/releases/2.6.0.md
git commit -m "Bump version to 2.6.0"
git tag v2.6.0
git push origin main --tags
```

The GitHub Action uses `docs/releases/<version>.md` when it exists. The same
notes are embedded in the Sparkle appcast and used as the GitHub Release body.
If the file is missing, the release falls back to generated placeholder notes.

The GitHub Action builds the DMG, creates or updates the GitHub Release, generates the signed update feed, and publishes `appcast.xml` to the `gh-pages` branch of this repository.
