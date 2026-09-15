# Release signing and notarization

GitHub Actions builds are signed and notarized before being attached to GitHub Releases. Configure these repository secrets before relying on release downloads:

- `BUILD_CERTIFICATE_BASE64`: Base64-encoded `.p12` export of the Developer ID Application certificate.
- `P12_PASSWORD`: Password for the exported `.p12`.
- `KEYCHAIN_PASSWORD`: Temporary CI keychain password. Any strong generated value is fine.
- `DEVELOPER_ID_APPLICATION`: Full signing identity, for example `Developer ID Application: Your Name (TEAMID)`.
- `APPLE_ID`: Apple Developer account email.
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `SPARKLE_PRIVATE_KEY`: Private EdDSA key exported by Sparkle's `generate_keys`
  tool. Keep this secret out of the repository.

Create `BUILD_CERTIFICATE_BASE64` locally after exporting the Developer ID Application certificate from Keychain Access:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

The workflow intentionally fails early when any signing secret is missing. Unsigned macOS downloads often show as damaged because Gatekeeper cannot verify the app.

## Publish an auto-update

The [CI workflow](../../.github/workflows/ci.yml) runs the repository gate
selector for every non-tag push and pull request. Branch pushes use the
`checkpoint` phase; pull requests and `main` use `integration`. CI has no
private Workshop corpus, so runtime-dependent gates are explicitly reported as
skipped there. CI never builds release artifacts, creates GitHub Releases, or
updates the Sparkle feed.

Pushing or merging to `main` does **not** publish a release. Publishing requires
an explicit `workflow_dispatch` of the [Release MyWallpaperX
workflow](../../.github/workflows/build.yml) against `main`. The public version
must already be committed in `MyWallpaperX.xcodeproj/project.pbxproj`; the
release workflow does not bump or commit project versions after publishing.

1. Create a release branch from current `main`.
2. Run `script/prepare_release_version.sh <version>` and open/merge that release
   PR.
3. After the release PR is merged, manually run **Release MyWallpaperX** against
   `main`.
4. The workflow resolves the public version from the Xcode project. If
   `build-<version>` already exists, the workflow fails and asks for a newer
   release version instead of auto-incrementing.
5. The workflow signs and notarizes the app, publishes the versioned DMG, signs
   `appcast.xml`, and replaces the `update-feed` release asset.

The release job is guarded to run only on `main`; dispatching it against another
ref does not publish. Installed release builds check the feed once per day and
can also use **检查更新…** from the application or status-bar menu.

## SteamService build and signing boundary

Xcode's App target publishes and embeds `Contents/Resources/SteamService/` in both
Debug and Release. Install SDK **8.0.401** (`SteamService/global.json`); CI selects
that version explicitly. The helper ships a pinned **.NET 8.0.31 osx-arm64** runtime,
so users do not need an SDK or runtime installation. NuGet restore is locked;
`SteamService/NOTICE.md` and `licenses/` accompany the generated directory.
Review runtime security updates independently of the fixed build SDK.

`script/publish-steam-helper.sh` publishes into a fresh temporary directory and
mirrors only a recognized generated helper output, removing stale dependencies.
Xcode's `TARGETNAME` must not change the managed entry assembly: the script fixes
`TargetName=SteamService` explicitly and rejects a missing `SteamService.dll`.
Per-build intermediates live in DerivedData, outside the source tree.

`script/sign-steam-helper.sh <helper-dir> <identity>` signs native dependencies
before the apphost. Real signing identities use hardened runtime and apphost
`com.apple.security.cs.allow-jit`; native libraries must have the same Team ID.
The outer App is signed after nested code, without `--deep --force` re-signing
that would overwrite helper entitlements. Ad-hoc `-` is a local, unhardened test
path because it has no Team ID for library validation. It does not prove the
Developer ID/notarization gate.

The arm64 bundle validator requires the helper, its runtime and license material.
A release still needs actual signed-bundle launch, full account/list/download
flow on the minimum supported Mac, notarization and Gatekeeper verification.
Build or offline self-tests do not close those gates.
