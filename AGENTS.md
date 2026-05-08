# Overview

`obsBotRemote` is a native macOS Swift project for bridging OBSBOT Smart Remote 2 HID input to OBSBOT Tiny-series camera controls.

The project is a Swift CLI lab bench that is growing into a small daemon built on Apple system frameworks.

Current status:

- remote HID capture, guided button mapping, JSON resume/reset, and live dry-run decoding are implemented;
- standard UVC `zoom-abs` and `pan-tilt-abs` lab commands are implemented through IOUSBLib control transfers;
- UVC extension-unit parsing and `camera-xu-get`/`camera-xu-dump` are implemented;
- OBSBOT run/sleep state is implemented through `camera-power`;
- `listen` is still dry-run and should not silently start changing hardware state without an explicit design change.

## Repository Layout

- `Package.swift` -- Swift Package Manager manifest.
- `Sources/ObsbotRemoteCore/` -- testable core types, USB discovery, camera state, UVC parsing, and UVC control logic.
- `Sources/ObsbotRemoteCLI/` -- CLI lab bench and future daemon entry point.
- `Sources/ObsbotRemoteSelfTest/` -- no-dependency self-test executable for bare Command Line Tools installs.
- `docs/` -- architecture and operational notes.
- `obsbot-remote-daemon-plan.md` -- initial research plan and hardware-discovery notes. Prefer current docs for status.
- `.github/workflows/ci.yml` -- macOS Swift build and test.

## Commands

```bash
swift build
swift run obsbot-remote-self-test
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons
swift run obsbot-remote map-buttons --reset
swift run obsbot-remote listen
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106
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

Use `swift build --configuration release` before packaging or Homebrew work.

## Design Notes

- Keep hardware access behind small adapters so tests stay hardware-free.
- Use IOHIDManager for remote dongle input and device seizure.
- Use IOKit/IOUSBLib for UVC camera-control transfers.
- OBSBOT vendor controls are UVC extension-unit packets. Keep the known selector/status details in docs when new controls are discovered.
- Unknown remote buttons should do nothing until keycodes are confirmed with the real dongle.
- Keep the CLI useful as a lab bench. Every hardware-discovery command should be directly reusable while building the daemon.

## Safety

- The tool must not take ownership of the camera video stream. Zoom, Meet, OBS, and similar apps should keep streaming while controls are sent.
- Commands that write camera state should be explicit and easy to trace.
- macOS privacy prompts are expected for HID access; do not try to bypass them.

## Documentation

- Keep `README.md` focused on setup, validation, and user-facing commands.
- Keep `docs/architecture.md` focused on the project boundary, runtime components, and future extraction points.
- Keep `docs/hardware-notes.md` current with observed USB ids, UVC descriptors, and external references used to derive vendor controls.
- Keep the markdown plan as the source for unresolved research questions, but update it when a direction changes.
- No emojis in code or docs.
- Commands on single lines unless line wrapping is needed for readability.
