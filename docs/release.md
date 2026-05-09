# Release Process

This project distributes `OBSBOT Remote.app` as a Developer ID signed and notarized macOS app. Homebrew distribution should use a cask that installs the released app archive.

References:

- [Apple Developer ID](https://developer.apple.com/support/developer-id/)
- [Signing Mac software with Developer ID](https://developer.apple.com/developer-id/)
- [Developer ID intermediate certificate updates](https://developer.apple.com/support/developer-id-intermediate-certificate/)
- [Apple Certificate Authority](https://www.apple.com/certificateauthority/)
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

## Create the Developer ID Application Certificate

Do this once per signing certificate. The certificate must be created from a Certificate Signing Request (CSR) generated on the Mac that will sign releases, because the private key stays in that Mac's keychain.

Create the CSR on the signing Mac:

1. Open **Keychain Access**.
2. In the menu bar, choose **Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority...**.
3. Enter the Apple ID email address for the developer account.
4. Enter `OBSBOT Remote Developer ID` as the common name.
5. Leave **CA Email Address** blank.
6. Select **Saved to disk**.
7. Select **Let me specify key pair information** if that option is shown.
8. Save the `.certSigningRequest` file.
9. If prompted for key pair information, use `2048 bits` and `RSA`.

Create the certificate on the Apple Developer website:

1. Open `developer.apple.com/account`.
2. Open **Certificates, Identifiers & Profiles**.
3. In the sidebar, open **Certificates**.
4. Click **+** to create a certificate.
5. Choose **Developer ID Application**.
6. On the **Select a Developer ID Certificate Intermediary** page, keep **G2 Sub-CA (Xcode 11.4.1 or later)** selected unless you need to sign for older macOS tooling.
7. Upload the `.certSigningRequest` file from the Mac.
8. Generate and download the `.cer` file.
9. Double-click the `.cer` file on the same Mac to install it in Keychain Access.
10. If Keychain Access asks where to add the certificate, choose the **login** keychain. Do not choose iCloud.

Verify the installed signing identity:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

Expected shape:

```text
Developer ID Application: ORGANIZATION NAME (TEAMID)
```

If Keychain Access shows the Developer ID Application certificate with the private key nested under it, but the certificate is marked **not trusted** and `security find-identity` reports `0 valid identities found`, install Apple's newer Developer ID G2 intermediate certificate:

```bash
curl -fsSLo /tmp/DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
open /tmp/DeveloperIDG2CA.cer
```

If Keychain Access asks where to add the Apple intermediate certificate, choose **System** if you have admin rights. The **login** keychain is acceptable if System is not available. Do not choose iCloud.

Then verify again:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## One-Time Notary Setup

Create a keychain profile for `notarytool`. This stores the Apple credentials in the local keychain so release commands do not need passwords on the command line.

Create the app-specific password first:

1. Open `account.apple.com/account/manage`.
2. Open **Sign-In and Security**.
3. Open **App-Specific Passwords**.
4. Create a password named `OBSBOT Remote Notary`.
5. Copy the generated password. Apple shows it once.

Store the notary credentials in the local keychain. Use the Apple ID email for the developer account and the Apple Developer Team ID.

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

The command can be run from any folder. It stores credentials under the profile name `obsbot-remote-notary`.

Verify that the stored profile can authenticate:

```bash
xcrun notarytool history --keychain-profile "obsbot-remote-notary"
```

An empty history is fine. Authentication errors are not.

## Version Update

Before building a release, update the app version in `scripts/build-menu-app.sh`:

- `CFBundleShortVersionString`: user-facing release version, such as `0.1.0`.
- `CFBundleVersion`: monotonically increasing build number, such as `1`.

Use a clean working tree before cutting a release:

```bash
git status --short
```

## Build, Sign, Notarize, and Package

Run release commands from the repository root.

Run the build and signing block:

```bash
VERSION="0.1.0"
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
NOTARY_PROFILE="obsbot-remote-notary"
APP=".build/OBSBOT Remote.app"
ARTIFACT_DIR=".build/release-artifacts"
NOTARY_ZIP="$ARTIFACT_DIR/OBSBOT-Remote-$VERSION-notary-upload.zip"
FINAL_ZIP="$ARTIFACT_DIR/OBSBOT-Remote-$VERSION.zip"

test -n "$IDENTITY"
printf 'Signing identity: %s\n' "$IDENTITY"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
swift build
swift run obsbot-remote-self-test
scripts/build-menu-app.sh release

codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

The local build script ad-hoc signs the app for development. The `codesign` command replaces that signature with the Developer ID signature and hardened runtime.

Run the notarization and final packaging block:

```bash
VERSION="0.1.0"
NOTARY_PROFILE="obsbot-remote-notary"
APP=".build/OBSBOT Remote.app"
ARTIFACT_DIR=".build/release-artifacts"
NOTARY_ZIP="$ARTIFACT_DIR/OBSBOT-Remote-$VERSION-notary-upload.zip"
FINAL_ZIP="$ARTIFACT_DIR/OBSBOT-Remote-$VERSION.zip"

mkdir -p "$ARTIFACT_DIR"
test -d "$APP"

ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP" "$FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP"
```

## GitHub Release

Create a tag and upload the final archive. Run this from the repository root after creating the final zip:

```bash
VERSION="0.1.0"
FINAL_ZIP=".build/release-artifacts/OBSBOT-Remote-$VERSION.zip"
SHA256="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"
NOTES_FILE="$(mktemp)"

test -f "$FINAL_ZIP"
git fetch --tags

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  echo "Tag v$VERSION already exists. Stop and inspect before continuing."
  exit 1
fi

if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "Release v$VERSION already exists. Stop and inspect before continuing."
  exit 1
fi

cat > "$NOTES_FILE" <<NOTES
OBSBOT Remote $VERSION

SHA256:

\`\`\`text
$SHA256
\`\`\`
NOTES

git tag "v$VERSION"
git push origin "v$VERSION"

gh release create "v$VERSION" "$FINAL_ZIP" \
  --title "OBSBOT Remote $VERSION" \
  --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"
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
