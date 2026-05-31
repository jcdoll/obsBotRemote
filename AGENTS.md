# Overview

`obsBotRemote` is a native macOS Swift project for bridging OBSBOT Smart Remote 2 HID input to OBSBOT Tiny-series camera controls.

The project provides a Swift CLI lab bench and a macOS menu bar app built on Apple system frameworks.

Current status:

- remote HID capture, guided button mapping, JSON resume/reset, live dry-run decoding, and foreground live control are implemented;
- standard UVC `zoom-abs` and `pan-tilt-abs` lab commands are implemented through IOUSBLib control transfers;
- UVC extension-unit parsing and `camera-xu-get`/`camera-xu-dump` are implemented;
- OBSBOT run/sleep state and AI mode toggles are implemented through `control`;
- the menu bar app includes a camera controls window for wake/sleep, pan/tilt, zoom, AI modes, and shared step sizes;
- `listen` is dry-run; `control` is live camera control.

## Repository Layout

- `Package.swift` -- Swift Package Manager manifest.
- `Resources/remote-button-capture.json` -- runtime default keymap for the OBSBOT Smart Remote 2.
- `Sources/ObsbotRemoteCore/` -- testable core types, USB discovery, camera state, UVC parsing, OBSBOT vendor protocol, and UVC control facade.
- `Sources/ObsbotRemoteControl/` -- shared remote button models, HID capture helpers, camera actions, and CLI live-control runtime.
- `Sources/ObsbotRemoteCLI/` -- CLI lab bench split by command dispatch, options, HID input, terminal input, button mapping, and camera commands.
- `Sources/ObsbotRemoteMenu/` -- menu bar app that registers remote shortcuts, starts/stops live remote control, opens camera controls, and displays logs.
- `Sources/ObsbotRemoteSelfTest/` -- no-dependency self-test executable for bare Command Line Tools installs.
- `docs/` -- architecture and operational notes.
- `docs/release.md` -- Developer ID, notarization, GitHub release, and Homebrew cask process.
- `.agents/skills/obsbot-release/` -- repo-local Codex skill for release packaging and distribution work.
- `scripts/build-menu-app.sh` -- local `.app` bundle builder for menu bar testing.
- `.github/workflows/ci.yml` -- macOS Swift build and test.

## Commands

```bash
swift build
swift run obsbot-remote-self-test
scripts/lint-swift-format.sh
scripts/install-git-hooks.sh
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons
swift run obsbot-remote map-buttons --reset
swift run obsbot-remote control
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
swift run obsbot-remote camera-reset
swift run obsbot-remote camera-xu-dump
swift run obsbot-remote camera-xu-get --unit 2 --selector 6 --length 60
swift run obsbot-remote uvc-controls
scripts/build-menu-app.sh
```

Use `swift build --configuration release` before packaging or Homebrew work.

## OBSBOT SDK Reference

- Official SDK page: <https://www.obsbot.com/sdk>. For Tiny-series webcam work, start from the SDK for OBSBOT Center. The page lists Tiny 3 as a compatible product and says the SDK supports macOS, Windows, and Linux.
- The SDK page may require OBSBOT sign-in or an SDK application. If the file is sent by email or downloaded by the browser, stage that exact zip locally before analysis. Prior work used an archive named like `libdev_v2_1_0_8.zip`; do not assume that remains current.
- Before adding or changing OBSBOT vendor controls, inspect the SDK headers and library behavior first. Do not infer selector-2 payloads, command ids, readback shapes, or enable/disable semantics from UI labels alone.
- Treat SDK internal command ids and wire command ids as separate concepts. Confirm the Tiny-series protocol version, command-set mapping, route bytes, packet flags, payload shape, and readback framing against the SDK before changing `OBSBOTProtocol` or gesture/image controls.
- Avoid broad AI shutdown APIs as substitutes for a specific feature toggle unless the SDK proves that is the intended control. For example, do not use a global AI enable/disable call just to disable hand gestures.

To grab and unpack the SDK for local inspection:

```bash
SDK_WORKDIR=/tmp/obsbot-sdk-read
mkdir -p "$SDK_WORKDIR"
curl -fL "$OBSBOT_SDK_URL" -o "$SDK_WORKDIR/obsbot-sdk.zip"
unzip -q "$SDK_WORKDIR/obsbot-sdk.zip" -d "$SDK_WORKDIR"
find "$SDK_WORKDIR" -type f \( -name '*.h' -o -name '*.hpp' -o -name '*.dylib' -o -name '*.so' -o -name '*.dll' \)
```

If the SDK was downloaded through the browser or received by email, replace the `curl` command with:

```bash
cp "$HOME/Downloads/<sdk-archive>.zip" "$SDK_WORKDIR/obsbot-sdk.zip"
```

Useful first-pass SDK inspection commands:

```bash
find "$SDK_WORKDIR" -type f \( -name '*.h' -o -name '*.hpp' \) -print0 | xargs -0 rg -n "Gesture|gesture|Ai|AI|UVC|DevGesture"
find "$SDK_WORKDIR" -type f -name '*.dylib' -print0 | xargs -0 nm -gU | rg "Gesture|gesture|Ai|AI|Track|track"
find "$SDK_WORKDIR" -type f -name '*.dylib' -print0 | xargs -0 strings | rg "Gesture|gesture|Track|track|selector|protocol"
```

## Design Notes

- Keep hardware access behind small adapters so tests stay hardware-free.
- Use IOHIDManager for CLI remote capture and device seizure.
- Use macOS global hotkeys for menu-app remote shortcut capture.
- Use IOKit/IOUSBLib for UVC camera-control transfers.
- OBSBOT vendor controls are UVC extension-unit packets. Keep the known selector/status details in docs when new controls are discovered.
- Keep `Sources/ObsbotRemoteCLI/main.swift` as process startup only. Add command behavior to focused files or `CommandLineTool` extensions.
- Keep `UVCController` as the high-level camera facade. Put descriptor parsing and OBSBOT packet construction in their dedicated core files.
- Unknown remote buttons should do nothing until keycodes are confirmed with the real dongle.
- Keep the CLI useful as a lab bench. Hardware-discovery commands should stay directly reusable.
- Keep the menu app in-process. It should not spawn the CLI for live control.

## Safety

- The tool must not take ownership of the camera video stream. Zoom, Meet, OBS, and similar apps should keep streaming while controls are sent.
- Commands that write camera state should be explicit and easy to trace.
- macOS privacy prompts are expected for CLI HID access; do not try to bypass them.

## Documentation

- Keep `README.md` focused on setup, validation, and user-facing commands.
- Keep `docs/architecture.md` focused on the project boundary, runtime components, and planned extraction points.
- Keep `docs/hardware-notes.md` current with observed USB ids, UVC descriptors, and external references used to derive vendor controls.
- Keep `docs/release.md` current with the signed/notarized app and Homebrew cask process.
- Describe the current project directly. Do not use historical framing, "growing into" language, or "proof of concept" labels unless quoting an external source.
- No emojis in code or docs.
- Commands on single lines unless line wrapping is needed for readability.
