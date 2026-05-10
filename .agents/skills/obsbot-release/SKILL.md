---
name: obsbot-release
description: Use when cutting, packaging, signing, notarizing, publishing, or Homebrew-distributing obsBotRemote or OBSBOT Remote.app, including Developer ID, notarytool, GitHub Releases, and Homebrew casks.
---

# obsBotRemote Release

Use this repo-local skill for release work only. The product release path is a Developer ID signed and notarized `OBSBOT Remote.app` distributed through a Homebrew cask.

This skill should be detailed enough for an agent to run the full release when the user explicitly asks for publishing. It covers the application repository, GitHub release, and Homebrew tap update. For normal releases, the user should only need to provide the version number.

## Source of Truth

Read these before release work:

- `docs/release.md` for release commands and checklist.
- `scripts/build-menu-app.sh` for app bundle construction and version fields.
- `AGENTS.md` for current project rules and repo layout.
- `README.md` for user-facing install instructions.

If release behavior changes, update `docs/release.md` first. Keep command blocks there and keep this skill focused on release sequencing, safety checks, and handoff points.

## Release Policy

- Use the cask-first path for normal users.
- Do not package the menu app as a Homebrew formula.
- Treat any CLI formula as separate and optional; only work on it if explicitly requested.
- Keep the app release artifact named `OBSBOT-Remote-$VERSION.zip`.
- Keep the app bundle named `OBSBOT Remote.app`.
- Keep the bundle identifier `com.jcdoll.obsbotremote` unless the user explicitly changes product identity.
- Keep the Homebrew cask token `obsbot-remote`.
- Keep the Homebrew tap path discoverable through `brew --repo jcdoll/tap`; do not hardcode a machine-local absolute path.

## Version-Driven Release Contract

When the user asks for a release and specifies a version, treat that version as the release input. Do not ask the user to manually edit release files.

For a requested `VERSION`:

- Infer `APP_VERSION="$VERSION"`.
- Increment `APP_BUILD` from the current default in `scripts/build-menu-app.sh` unless the user specifies a build number.
- Update the default `APP_VERSION` and `APP_BUILD` in `scripts/build-menu-app.sh`.
- Update `docs/release.md` examples and Homebrew commit text to the requested version.
- Use artifact name `OBSBOT-Remote-$VERSION.zip`.
- Use tag and GitHub release name `v$VERSION`.
- Update `Casks/obsbot-remote.rb` in `$(brew --repo jcdoll/tap)` to the requested version and the final zip SHA256.
- Verify no stale previous release version remains in release instructions, app bundle metadata, or the cask where it would mislead the next release.

## Operating Rules

- Before editing release files, inspect `git status --short`.
- Do not begin a release from a dirty tree unless the user explicitly confirms the included changes.
- For commands that use Apple credentials, signing identities, notarization, GitHub release publishing, Homebrew install/uninstall, or tap pushes, default to giving the user a pasteable command block unless they explicitly ask Codex to run it.
- If the user asks Codex to run publishing commands, state exactly which remote action is about to happen before running it.
- Never overwrite existing tags, GitHub releases, or Homebrew tap commits without explicit confirmation.
- Stop on signing, notarization, or Gatekeeper failures and surface the exact failing command and output.
- Do not commit certificate files, app-specific passwords, Apple ID emails, Team IDs, `.p12` files, `.cer` files, generated zips, `.app` bundles, or `.build` output.
- Keep the product repository public before testing Homebrew install from a GitHub release asset. Private release assets produce Homebrew download failures.

## Required Inputs

Before a full release, confirm or discover:

- `VERSION`, such as `0.2.0`. This should be the only required user input for a normal release.
- `APP_VERSION` and `APP_BUILD` defaults in `scripts/build-menu-app.sh`.
- Developer ID signing identity from `security find-identity -v -p codesigning`.
- Notary keychain profile name, currently `obsbot-remote-notary`.
- GitHub CLI authentication with release permissions for `jcdoll/obsBotRemote`.
- Homebrew tap availability at `jcdoll/tap`.

## Full Release Sequence

Use this sequence for a complete release:

1. Preflight app repo:
   - `git status --short`
   - `scripts/lint-swift-format.sh`
   - `swift build`
   - `swift run obsbot-remote-self-test`
   - `swift build --configuration release`
2. Confirm version:
   - Check `APP_VERSION` and `APP_BUILD` in `scripts/build-menu-app.sh`.
   - Check that `v$VERSION` does not already exist locally, remotely, or as a GitHub release.
3. Build and sign:
   - Run the build/signing block from `docs/release.md`.
   - Verify `codesign --verify --deep --strict --verbose=2 ".build/OBSBOT Remote.app"`.
4. Notarize and package:
   - Run the notarization block from `docs/release.md`.
   - Verify `xcrun stapler validate`, `spctl --assess`, and `shasum -a 256`.
   - Record the final archive path and SHA256.
5. Publish GitHub release:
   - Tag `v$VERSION`.
   - Push the tag.
   - Create the GitHub release with the final zip attached.
   - Confirm the release asset URL resolves publicly before testing Homebrew.
6. Update Homebrew tap:
   - Go to `$(brew --repo jcdoll/tap)`.
   - Update `Casks/obsbot-remote.rb` version and SHA256.
   - Keep the URL shape `https://github.com/jcdoll/obsBotRemote/releases/download/v#{version}/OBSBOT-Remote-#{version}.zip`.
   - Run `brew audit --cask obsbot-remote`.
   - Run `brew install --cask obsbot-remote`.
   - Run `brew uninstall --cask obsbot-remote`.
   - Commit and push the tap.
7. Final verification:
   - Fresh user command should work: `brew tap jcdoll/tap && brew install --cask obsbot-remote`.
   - The installed app should launch as `OBSBOT Remote`.
   - App Gatekeeper assessment should show a notarized Developer ID source.

## Validation Checklist

Before marking a release ready:

- `scripts/lint-swift-format.sh` passes.
- `swift build` passes.
- `swift run obsbot-remote-self-test` passes.
- `swift build --configuration release` passes.
- `scripts/build-menu-app.sh release` creates `.build/OBSBOT Remote.app`.
- Developer ID signing uses hardened runtime and timestamp.
- `codesign --verify --deep --strict --verbose=2 ".build/OBSBOT Remote.app"` passes.
- `xcrun notarytool submit ... --wait` is accepted.
- `xcrun stapler validate ".build/OBSBOT Remote.app"` passes.
- `spctl --assess --type execute --verbose=4 ".build/OBSBOT Remote.app"` accepts the app.
- GitHub release `v$VERSION` exists and contains `OBSBOT-Remote-$VERSION.zip`.
- The release asset URL is downloadable without private repository credentials.
- The final `sha256` in the Homebrew cask matches the stapled final archive.
- Homebrew audit, install, and uninstall pass.
- Do not use `brew audit --cask --new` for this project tap. That flag applies upstream Homebrew notability checks.

## Homebrew Cask Shape

Use this cask structure unless the project metadata changes:

```ruby
cask "obsbot-remote" do
  version "0.2.0"
  sha256 "REPLACE_WITH_FINAL_ZIP_SHA256"

  url "https://github.com/jcdoll/obsBotRemote/releases/download/v#{version}/OBSBOT-Remote-#{version}.zip"
  name "OBSBOT Remote"
  desc "Menu bar controller for OBSBOT Smart Remote 2 and OBSBOT Tiny-series cameras"
  homepage "https://github.com/jcdoll/obsBotRemote"

  depends_on macos: ">= :ventura"

  app "OBSBOT Remote.app"
end
```

## Failure Handling

- If `security find-identity` finds no valid Developer ID identity, stop and use `docs/release.md` certificate setup instructions.
- If the Developer ID certificate is present but not trusted, install Apple's Developer ID G2 intermediate certificate as documented in `docs/release.md`.
- If `notarytool submit` fails, fetch the notary log before retrying and surface the status to the user.
- If Homebrew download returns 404, verify the product repository and GitHub release asset are public.
- If `brew audit --cask --new` fails on project notability, rerun the project tap check as `brew audit --cask obsbot-remote`.
- If `brew audit` fails due to local Homebrew dependency state, repair Homebrew first; do not work around cask validation.
