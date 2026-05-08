# Overview

`obsBotRemote` is a native macOS Swift project for bridging OBSBOT Smart Remote 2 HID input to OBSBOT Tiny 2 camera controls.

This repository deliberately avoids Python, `uvc-util`, `pynput`, libusb, Qt, and the OBSBOT SDK for the product path. The final shape should be a small Swift CLI/daemon built on Apple system frameworks.

## Repository Layout

- `Package.swift` -- Swift Package Manager manifest.
- `Sources/ObsbotRemoteCore/` -- testable core types, USB discovery, camera state, and future UVC control logic.
- `Sources/ObsbotRemoteCLI/` -- CLI lab bench and future daemon entry point.
- `Sources/ObsbotRemoteSelfTest/` -- no-dependency self-test executable for bare Command Line Tools installs.
- `docs/` -- architecture and operational notes.
- `obsbot-remote-daemon-plan.md` -- research plan and hardware-discovery notes. Treat old Python/uvc-util sections as historical unless explicitly marked current.
- `.github/workflows/ci.yml` -- macOS Swift build and test.

## Commands

```bash
swift build
swift run obsbot-remote-self-test
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons
```

Use `swift build --configuration release` before packaging or Homebrew work.

## Design Notes

- Keep hardware access behind small adapters so tests stay hardware-free.
- Use IOHIDManager for remote dongle input. Device seizure belongs here, not in a Python listener.
- Use IOKit for UVC camera-control transfers. Do not add libusb unless direct IOKit proves impossible.
- `uvc-util` is acceptable as a reference implementation only; do not make it a user-installed dependency.
- Unknown remote buttons should do nothing until keycodes are confirmed with the real dongle.
- Keep the CLI useful as a lab bench. Every hardware-discovery command should be directly reusable while building the daemon.

## Safety

- The tool must not take ownership of the camera video stream. Zoom, Meet, OBS, and similar apps should keep streaming while controls are sent.
- Commands that write camera state should be explicit and easy to trace.
- macOS privacy prompts are expected for HID access; do not try to bypass them.

## Documentation

- Keep `README.md` focused on setup, validation, and user-facing commands.
- Keep `docs/architecture.md` focused on the project boundary, runtime components, and future extraction points.
- Keep the markdown plan as the source for unresolved research questions, but update it when a direction changes.
- No emojis in code or docs.
- Commands on single lines unless line wrapping is needed for readability.
