# OBSBOT Remote

Native macOS menu bar controller for using the OBSBOT Smart Remote 2 with an OBSBOT Tiny-series camera.

The app starts remote control when launched. It listens for the remote's enabled keyboard shortcuts, maps them through `Resources/remote-button-capture.json`, and sends camera controls through Apple system frameworks.

## Install

Install with Homebrew:

```bash
brew tap jcdoll/tap
brew install --cask obsbot-remote
open -a "OBSBOT Remote"
```

Connect the OBSBOT Smart Remote 2 USB dongle and the OBSBOT camera before launching the app. The menu bar video icon opens the app menu with Start/Stop, Log, and Quit.

Uninstall:

```bash
brew uninstall --cask obsbot-remote
```

## Developer Setup

Install Apple's Command Line Tools or Xcode, then validate the Swift package:

```bash
swift build
swift run obsbot-remote-self-test
swift format lint --recursive --strict Package.swift Sources
```

Build and run the menu bar app locally:

```bash
scripts/build-menu-app.sh
open ".build/OBSBOT Remote.app"
```

Install a local development build without Homebrew:

```bash
scripts/build-menu-app.sh release
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/OBSBOT Remote.app"
ditto ".build/OBSBOT Remote.app" "$HOME/Applications/OBSBOT Remote.app"
open "$HOME/Applications/OBSBOT Remote.app"
```

Local builds are ad-hoc signed for development. Developer ID signing, notarization, GitHub release creation, and Homebrew cask updates are documented in [docs/release.md](docs/release.md).

## Remote Key Setup

Normal Homebrew users do not need to run key capture. The app ships with the default Smart Remote 2 keymap.

Developers should re-capture the keymap when setting up a different remote revision or changing enabled/disabled button behavior. The keymap lives at `Resources/remote-button-capture.json`.

Check local device visibility, then run the guided key capture:

```bash
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons --reset
```

The command prompts for each known remote button and writes `Resources/remote-button-capture.json`. Press Return to arm each capture window, press and release the named remote button, then continue through the prompts.

Verify the keymap without moving the camera:

```bash
swift run obsbot-remote listen
```

Run live terminal control:

```bash
swift run obsbot-remote control
```

Rebuild the menu app after changing `Resources/remote-button-capture.json` so the app bundle includes the new keymap:

```bash
scripts/build-menu-app.sh
open ".build/OBSBOT Remote.app"
```

Raw HID sniffing is available when debugging remote input:

```bash
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106
```

The button map and enabled/disabled controls are described in [docs/remote-button-map.md](docs/remote-button-map.md).

## Camera Lab Commands

List attached USB devices:

```bash
swift run obsbot-remote devices
```

Probe camera controls:

```bash
swift run obsbot-remote camera-probe
```

Read or adjust zoom:

```bash
swift run obsbot-remote camera-zoom
swift run obsbot-remote camera-zoom --delta 10
```

Move the gimbal by raw UVC pan/tilt values:

```bash
swift run obsbot-remote camera-pan-tilt --pan <raw> --tilt <raw>
```

Read or toggle sleep/wake:

```bash
swift run obsbot-remote camera-power status
swift run obsbot-remote camera-power
swift run obsbot-remote camera-power on
swift run obsbot-remote camera-power off
```

Inspect OBSBOT extension-unit controls:

```bash
swift run obsbot-remote camera-xu-dump
swift run obsbot-remote camera-xu-get --unit 2 --selector 6 --length 60
```

## Project Layout

- `Resources/remote-button-capture.json` -- default Smart Remote 2 keymap.
- `Sources/ObsbotRemoteCore/` -- USB discovery, UVC parsing, camera state, and OBSBOT vendor protocol.
- `Sources/ObsbotRemoteControl/` -- shared remote button matching and camera action execution.
- `Sources/ObsbotRemoteCLI/` -- command-line lab bench.
- `Sources/ObsbotRemoteMenu/` -- menu bar app.
- `Sources/ObsbotRemoteSelfTest/` -- no-dependency self-test executable.
- `docs/architecture.md` -- project architecture.
- `docs/hardware-notes.md` -- observed USB ids, descriptors, and vendor-control notes.
- `docs/release.md` -- signed app and Homebrew release process.

## References

- [OBSBOT SDK](https://www.obsbot.com/sdk)
- [aaronsb/obsbot-camera-control](https://github.com/aaronsb/obsbot-camera-control)
- [cgevans/tiny2](https://github.com/cgevans/tiny2)
- [samliddicott/meet4k](https://github.com/samliddicott/meet4k)
