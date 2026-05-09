---
name: obsbot-release
description: Use when cutting, packaging, signing, notarizing, publishing, or Homebrew-distributing obsBotRemote or OBSBOT Remote.app, including Developer ID, notarytool, GitHub Releases, and Homebrew casks.
---

# obsBotRemote Release

Use this repo-local skill for release work only. The product release path is a Developer ID signed and notarized `OBSBOT Remote.app` distributed through a Homebrew cask.

## Source of Truth

Read these before release work:

- `docs/release.md` for release commands and checklist.
- `scripts/build-menu-app.sh` for app bundle construction and version fields.
- `AGENTS.md` for current project rules and repo layout.

If release behavior changes, update `docs/release.md` first. Keep this skill as a short workflow trigger, not a duplicate release manual.

## Release Policy

- Use the cask-first path for normal users.
- Do not package the menu app as a Homebrew formula.
- Treat any CLI formula as separate and optional; only work on it if explicitly requested.
- Keep the app release artifact named `OBSBOT-Remote-$VERSION.zip`.
- Keep the app bundle named `OBSBOT Remote.app`.
- Keep the bundle identifier `com.jcdoll.obsbotremote` unless the user explicitly changes product identity.

## Operating Rules

- Before editing release files, inspect `git status --short`.
- For commands that use Apple credentials, signing identities, notarization, GitHub release publishing, Homebrew install/uninstall, or tap pushes, default to giving the user a pasteable command block unless they explicitly ask Codex to run it.
- If the user asks Codex to run publishing commands, state exactly which remote action is about to happen before running it.
- Never overwrite existing tags, GitHub releases, or Homebrew tap commits without explicit confirmation.
- Stop on signing, notarization, or Gatekeeper failures and surface the exact failing command and output.

## Validation Checklist

Before marking a release ready:

- `swift build` passes.
- `swift run obsbot-remote-self-test` passes.
- `scripts/build-menu-app.sh release` creates `.build/OBSBOT Remote.app`.
- Developer ID signing uses hardened runtime and timestamp.
- `codesign --verify --deep --strict --verbose=2 ".build/OBSBOT Remote.app"` passes.
- `xcrun notarytool submit ... --wait` is accepted.
- `xcrun stapler validate ".build/OBSBOT Remote.app"` passes.
- `spctl --assess --type execute --verbose=4 ".build/OBSBOT Remote.app"` accepts the app.
- The final `sha256` in the Homebrew cask matches the stapled final archive.

## Homebrew Cask Shape

Use this cask structure unless the project metadata changes:

```ruby
cask "obsbot-remote" do
  version "0.1.0"
  sha256 "REPLACE_WITH_FINAL_ZIP_SHA256"

  url "https://github.com/jcdoll/obsBotRemote/releases/download/v#{version}/OBSBOT-Remote-#{version}.zip"
  name "OBSBOT Remote"
  desc "Menu bar controller for OBSBOT Smart Remote 2 and OBSBOT Tiny-series cameras"
  homepage "https://github.com/jcdoll/obsBotRemote"

  depends_on macos: ">= :ventura"

  app "OBSBOT Remote.app"
end
```
