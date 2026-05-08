# obsBotRemote

Native macOS lab bench and daemon for using the OBSBOT Smart Remote 2 with an OBSBOT Tiny 2 without running OBSBOT Center.

The project is Swift-first. It uses Apple system frameworks directly: IOHIDManager for the remote dongle and IOKit for camera controls. Python and `uvc-util` are no longer part of the product path.

## Setup

Install Apple's Command Line Tools or Xcode, then build with Swift Package Manager:

```bash
swift build
swift run obsbot-remote-self-test
```

## Lab Bench Commands

```bash
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons
swift run obsbot-remote listen
swift run obsbot-remote camera-probe
swift run obsbot-remote camera-zoom
swift run obsbot-remote camera-zoom --delta 10
swift run obsbot-remote camera-pan-tilt --pan <raw> --tilt <raw>
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106 --seize
swift run obsbot-remote uvc-controls
```

Use `devices` first to identify the remote dongle and camera vendor/product ids. Use `map-buttons` for guided button capture, then `listen` to decode live remote input into dry-run actions. Use `hid-sniff` only when you want a raw event stream.

`camera-probe`, `camera-zoom`, and `camera-pan-tilt` use native UVC control transfers through Apple system frameworks. No `uvc-util` or Python helper is required.

Observed local hardware ids are tracked in [docs/hardware-notes.md](docs/hardware-notes.md).
Remote button capture is tracked in [docs/remote-button-map.md](docs/remote-button-map.md).

## Development

```bash
swift build
swift run obsbot-remote-self-test
swift build --configuration release
```

For implementation details, see [docs/architecture.md](docs/architecture.md). The original discovery plan is in [obsbot-remote-daemon-plan.md](obsbot-remote-daemon-plan.md).
