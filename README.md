# obsBotRemote

Native macOS CLI and menu bar controller for using the OBSBOT Smart Remote 2 with an OBSBOT Tiny-series camera without running OBSBOT Center.

The project is Swift-first. It uses Apple system frameworks directly: IOHIDManager for the remote dongle and IOKit/IOUSBLib for camera controls.

Current status:

- remote button capture, dry-run decoding, and foreground live control are working;
- the default remote button keymap lives in `Resources/remote-button-capture.json` and supports disabled captures;
- standard UVC zoom and pan/tilt lab commands are working;
- OBSBOT vendor extension-unit probing is working;
- OBSBOT sleep/wake is working through `control`; AI tracking mode buttons are mapped for testing;
- the menu bar app can start/stop the live control process and show logs.

## Setup

Install Apple's Command Line Tools or Xcode, then build with Swift Package Manager:

```bash
swift build
swift run obsbot-remote-self-test
```

## Lab Bench Commands

Build and local validation:

```bash
swift build
swift run obsbot-remote-self-test
swift build --configuration release
```

Menu bar app:

```bash
scripts/build-menu-app.sh
open ".build/OBSBOT Remote.app"
```

Click the menu bar video icon to start or stop live remote control, open the log, or quit. The menu app opens the remote dongle in normal HID listening mode and does not block remote keystrokes from reaching other apps. macOS may ask for Input Monitoring access before HID listening is allowed.

Remote discovery and mapping:

```bash
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons
swift run obsbot-remote map-buttons --reset
swift run obsbot-remote control
swift run obsbot-remote listen
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106 --seize
```

Camera lab commands:

```bash
swift run obsbot-remote camera-probe
swift run obsbot-remote camera-zoom
swift run obsbot-remote camera-zoom --delta 10
swift run obsbot-remote camera-pan-tilt --pan <raw> --tilt <raw>
swift run obsbot-remote camera-power status
swift run obsbot-remote camera-power
swift run obsbot-remote camera-power on
swift run obsbot-remote camera-power off
swift run obsbot-remote camera-xu-dump
swift run obsbot-remote camera-xu-get --unit 2 --selector 6 --length 60
swift run obsbot-remote uvc-controls
```

Use `devices` first to identify the remote dongle and camera vendor/product ids. Use `map-buttons` for guided button capture, `listen` to decode remote input without moving the camera, and `control` when you want terminal-based remote control. Use `hid-sniff` only when you want a raw event stream.

`camera-probe`, `camera-zoom`, `camera-pan-tilt`, and `camera-power` use native UVC control transfers through Apple system frameworks.
`control` maps the remote's Track, Close-up, Hand Track, and Desk Mode buttons to OBSBOT AI modes.

Observed local hardware ids are tracked in [docs/hardware-notes.md](docs/hardware-notes.md).
Remote button mapping is described in [docs/remote-button-map.md](docs/remote-button-map.md).

## References

The implementation direction is documented in [docs/architecture.md](docs/architecture.md) and [docs/hardware-notes.md](docs/hardware-notes.md). External references used for the OBSBOT extension-unit work:

- [OBSBOT SDK](https://www.obsbot.com/sdk)
- [aaronsb/obsbot-camera-control](https://github.com/aaronsb/obsbot-camera-control)
- [cgevans/tiny2](https://github.com/cgevans/tiny2)
- [samliddicott/meet4k](https://github.com/samliddicott/meet4k)

## Development

```bash
swift build
swift run obsbot-remote-self-test
swift build --configuration release
```

For implementation details, see [docs/architecture.md](docs/architecture.md).

## Distribution Notes

The Swift package exposes separate executables for the CLI, menu bar app, and self-test. `scripts/build-menu-app.sh` wraps the menu executable as a local `.app` bundle. The intended Homebrew path is a formula for the CLI and a cask for the signed menu app bundle.
