# Architecture

`obsBotRemote` is a native macOS remote-control daemon in progress. It listens for OBSBOT Smart Remote 2 HID input and translates known button presses into camera controls for an OBSBOT Tiny 2.

## Project Boundary

The final product should be a single Swift-built CLI/daemon that depends on Apple system frameworks, not on Python or source-built helper tools.

Out of scope:

- Python runtime, `pynput`, or uv-managed environments;
- user-installed `uvc-util`;
- libusb/libuvc unless direct IOKit control proves impossible;
- Qt, camera preview, virtual camera output, or OBSBOT SDK integration.

## Runtime Shape

```text
Smart Remote 2 USB dongle
        |
        v
IOHIDManager device match/seize
        |
        v
HID event decoder
        |
        v
keymap / action dispatcher
        |
        v
camera controller
        |
        v
IOKit UVC control transfer
        |
        v
OBSBOT Tiny 2
```

The current Swift CLI is the lab bench. It lists USB devices, sniffs HID events, decodes live remote input, probes UVC descriptors, and can issue native UVC `GET_CUR`/`SET_CUR` requests for `pan-tilt-abs` and `zoom-abs`.

## Components

`ObsbotRemoteCore` owns testable logic:

- camera state and action reduction;
- numeric parsing and hex formatting;
- IOKit USB device discovery;
- UVC descriptor parsing and direct USB control requests.

`ObsbotRemoteUSBBridge` is a small C target that wraps IOUSBLib calls needed for USB configuration descriptors and control requests. Swift owns the UVC parsing and command decisions.

`ObsbotRemoteCLI` owns operator commands:

- `doctor` checks local assumptions;
- `devices` lists USB devices visible through IOKit;
- `hid-sniff` records remote HID events;
- `listen` decodes live remote input into dry-run camera actions;
- `camera-probe` finds UVC VideoControl interfaces and camera-terminal controls;
- `camera-zoom` reads or writes `zoom-abs`;
- `camera-pan-tilt` writes `pan-tilt-abs`;
- `uvc-controls` reports the native UVC implementation status.

## Lab Bench Strategy

The lab bench should be easy to run after cloning:

```bash
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons
swift run obsbot-remote listen
swift run obsbot-remote camera-probe
```

No external camera-control binary should be required. `uvc-util` remains useful as a reference implementation because it demonstrates direct IOKit UVC control, but users should not have to install it.

## Safety Model

The daemon controls camera state but must not take ownership of the video stream. Zoom, Meet, OBS, and other apps should still use the camera while this daemon adjusts supported controls.

HID device seizure is expected for the final daemon because it prevents remote keypresses from leaking into the focused app. macOS may require user approval for input monitoring or related privacy permissions.

## Test Strategy

CI tests stay hardware-free. The project currently uses a no-dependency `obsbot-remote-self-test` executable instead of XCTest so validation works on bare Apple Command Line Tools installs. Test pure logic and command-adjacent parsing there. Hardware validation remains manual until the project has injectable IOKit boundaries.

CI runs on macOS only because the package imports IOKit.

## Future Extraction Points

Keep the package small until hardware behavior is known:

- `HIDRemoteReader` for IOHIDManager matching, seizure, and callbacks;
- `Keymap` for mapping confirmed HID usage values to camera actions;
- shared command loop that connects decoded buttons to `UVCController`;
- LaunchAgent installation docs or templates;
- Homebrew formula once the release binary is useful.
