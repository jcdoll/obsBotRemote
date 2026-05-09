# Architecture

`obsBotRemote` is a native macOS remote-control daemon in progress. It listens for OBSBOT Smart Remote 2 HID input and translates known button presses into camera controls for an OBSBOT Tiny 2.

## Project Shape

The project is a Swift CLI lab bench that is growing into a small macOS daemon. It uses Apple system frameworks for remote input and camera control.

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

The current Swift CLI is the lab bench. It lists USB devices, sniffs HID events, decodes live remote input, probes UVC descriptors, and can issue native UVC `GET_CUR`/`SET_CUR` requests for `pan-tilt-abs`, `zoom-abs`, and OBSBOT vendor extension-unit controls.

## Components

`ObsbotRemoteCore` owns testable logic:

- camera state and action reduction;
- numeric parsing and hex formatting;
- IOKit USB device discovery;
- UVC descriptor parsing;
- OBSBOT vendor packet construction;
- direct USB control requests exposed through `UVCController`.

`ObsbotRemoteUSBBridge` is a small C target that wraps IOUSBLib calls needed for USB configuration descriptors and control requests. Swift owns the UVC parsing and command decisions.

`ObsbotRemoteCLI` owns operator commands:

- `doctor` checks local assumptions;
- `devices` lists USB devices visible through IOKit;
- `hid-sniff` records remote HID events;
- `control` runs foreground live remote-to-camera control;
- `listen` decodes live remote input into dry-run camera actions;
- `camera-probe` finds UVC VideoControl interfaces and camera-terminal controls;
- `camera-zoom` reads or writes `zoom-abs`;
- `camera-pan-tilt` writes `pan-tilt-abs`;
- `camera-power` reads or toggles OBSBOT run/sleep state through the vendor extension unit;
- `camera-xu-get` and `camera-xu-dump` inspect UVC extension-unit selectors;
- `uvc-controls` reports the native UVC implementation status.

CLI implementation is split by concern:

- `main.swift` owns process startup and error handling;
- `CommandLineTool.swift` owns command dispatch and help text;
- `CommandOptions.swift` owns argument parsing;
- `HIDCommands.swift`, `HIDRemoteInput.swift`, and `TerminalInput.swift` own remote capture and terminal input;
- `ButtonMapping.swift` owns capture JSON models, matching, and dry-run action labels;
- `CameraCommands.swift` owns camera-facing lab commands.

## Lab Bench Strategy

The lab bench should be easy to run after cloning:

```bash
swift run obsbot-remote doctor
swift run obsbot-remote devices
swift run obsbot-remote map-buttons
swift run obsbot-remote control
swift run obsbot-remote listen
swift run obsbot-remote camera-probe
swift run obsbot-remote camera-power status
```

## External References

These references informed the current UVC extension-unit work:

- [OBSBOT SDK](https://www.obsbot.com/sdk): documents SDK support for universal sleep/wake and Tiny-series device sleep features.
- [aaronsb/obsbot-camera-control](https://github.com/aaronsb/obsbot-camera-control): Linux controller with bundled OBSBOT SDK headers and UVC extension-unit notes.
- [cgevans/tiny2](https://github.com/cgevans/tiny2): Linux Tiny 2 controller that writes 60-byte OBSBOT vendor packets through UVC extension unit 2 selector 2.
- [samliddicott/meet4k](https://github.com/samliddicott/meet4k): documents OBSBOT selector data as RPC-like state rather than simple write-back memory.

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
