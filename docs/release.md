# Release Process

This project distributes `OBSBOT Remote.app` as a Developer ID signed and notarized macOS app. Homebrew distribution should use a cask that installs the released app archive.

References:

- [Apple Developer ID](https://developer.apple.com/support/developer-id/)
- [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)

## Requirements

- Apple Developer Program membership.
- Xcode installed and selected with `xcode-select`.
- A `Developer ID Application` certificate installed in the local keychain.
- An App Store Connect app-specific password or equivalent notary credentials.
- `gh` installed and authenticated if using the GitHub CLI release commands.

Check local signing identities:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Check Xcode:

```bash
xcode-select -p
xcrun notarytool --version
```

## One-Time Notary Setup

Create a keychain profile for `notarytool`. This stores the Apple credentials in the local keychain so release commands do not need passwords on the command line.

```bash
read -r -p "Apple ID email: " APPLE_ID
read -r -p "Apple Developer Team ID: " TEAM_ID
read -r -s -p "App-specific password: " APP_PASSWORD
echo

xcrun notarytool store-credentials "obsbot-remote-notary" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD"

unset APP_PASSWORD
```

## Version Update

Before building a release, update the app version in `scripts/build-menu-app.sh`:

- `CFBundleShortVersionString`: user-facing release version, such as `0.1.0`.
- `CFBundleVersion`: monotonically increasing build number, such as `1`.

Use a clean working tree before cutting a release:

```bash
git status --short
```

## Build, Sign, Notarize, and Package

Set release variables. Replace `IDENTITY` with the exact certificate name from `security find-identity`.

```bash
VERSION="0.1.0"
IDENTITY="Developer ID Application: YOUR NAME (TEAMID)"
NOTARY_PROFILE="obsbot-remote-notary"
APP=".build/OBSBOT Remote.app"
ARTIFACT_DIR=".build/release-artifacts"
NOTARY_ZIP="$ARTIFACT_DIR/OBSBOT-Remote-$VERSION-notary-upload.zip"
FINAL_ZIP="$ARTIFACT_DIR/OBSBOT-Remote-$VERSION.zip"
```

Build the app bundle:

```bash
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

swift build
swift run obsbot-remote-self-test
scripts/build-menu-app.sh release
```

The local build script ad-hoc signs the app for development. Replace that signature with the Developer ID signature and hardened runtime:

```bash
codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

Create the archive to submit to Apple:

```bash
ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
```

Submit and wait for notarization:

```bash
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
```

Staple the accepted ticket to the app bundle, then validate it:

```bash
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
```

Create the final user-facing archive after stapling:

```bash
rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP"
```

## GitHub Release

Create a tag and upload the final archive:

```bash
git tag "v$VERSION"
git push origin "v$VERSION"

gh release create "v$VERSION" "$FINAL_ZIP" \
  --title "OBSBOT Remote $VERSION" \
  --notes "Release $VERSION"
```

If the tag already exists locally or remotely, stop and inspect before overwriting anything.

## Homebrew Cask

Create a tap if one does not already exist:

```bash
brew tap-new jcdoll/tap
```

Create `Casks/obsbot-remote.rb` in that tap:

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

Test the cask locally:

```bash
cd "$(brew --repo jcdoll/tap)"
brew audit --cask --new obsbot-remote
brew install --cask obsbot-remote
brew uninstall --cask obsbot-remote
```

Push the tap:

```bash
cd "$(brew --repo jcdoll/tap)"
git status --short
git add Casks/obsbot-remote.rb
git commit -m "Add obsbot-remote cask"
git push
```

Users install with:

```bash
brew tap jcdoll/tap
brew install --cask obsbot-remote
```

## Release Checklist

- `swift build` passes.
- `swift run obsbot-remote-self-test` passes.
- `scripts/build-menu-app.sh release` creates `OBSBOT Remote.app`.
- `codesign --verify --deep --strict` passes.
- `notarytool submit --wait` returns accepted.
- `stapler validate` passes.
- `spctl --assess --type execute` accepts the app.
- GitHub release contains the final stapled archive.
- Homebrew cask `sha256` matches the final archive.
