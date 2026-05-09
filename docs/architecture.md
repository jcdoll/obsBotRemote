# Architecture

`obsBotRemote` is a native macOS CLI and menu bar controller. It translates known OBSBOT Smart Remote 2 button presses into camera controls for an OBSBOT Tiny 2.

## Project Shape

The project uses Apple system frameworks for remote input and camera control. The CLI uses IOHIDManager for remote capture and mapping. The menu app registers the remote's enabled keyboard shortcuts as global hotkeys.

## Runtime Shape

```text
Smart Remote 2 USB dongle
        |
        v
keyboard shortcut or IOHID event
        |
        v
hotkey / HID decoder
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

The Swift CLI lists USB devices, sniffs HID events, decodes live remote input, probes UVC descriptors, and can issue native UVC `GET_CUR`/`SET_CUR` requests for `pan-tilt-abs`, `zoom-abs`, and OBSBOT vendor extension-unit controls.

## Components

`ObsbotRemoteCore` owns testable logic:

- camera state and action reduction;
- numeric parsing and hex formatting;
- IOKit USB device discovery;
- UVC descriptor parsing;
- OBSBOT vendor packet construction;
- direct USB control requests exposed through `UVCController`.

`ObsbotRemoteControl` owns shared live-control logic:

- remote button capture models and matching;
- HID manager helpers and event collection;
- remote-button to camera-action mapping;
- foreground HID live control session used by the CLI.

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

`ObsbotRemoteMenu` owns the menu bar app. It runs as an accessory app, starts live control on launch, exposes a status menu, stops/restarts live control, displays logs, and registers enabled remote shortcuts from `Resources/remote-button-capture.json` as macOS global hotkeys.

CLI implementation is split by concern:

- `main.swift` owns process startup and error handling;
- `CommandLineTool.swift` owns command dispatch and help text;
- `CommandOptions.swift` owns argument parsing;
- `HIDCommands.swift`, `CLIRemoteInput.swift`, and `TerminalInput.swift` own CLI remote capture and terminal input;
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
scripts/build-menu-app.sh
```

## External References

These references informed the current UVC extension-unit work:

- [OBSBOT SDK](https://www.obsbot.com/sdk): documents SDK support for universal sleep/wake and Tiny-series device sleep features.
- [aaronsb/obsbot-camera-control](https://github.com/aaronsb/obsbot-camera-control): Linux controller with bundled OBSBOT SDK headers and UVC extension-unit notes.
- [cgevans/tiny2](https://github.com/cgevans/tiny2): Linux Tiny 2 controller that writes 60-byte OBSBOT vendor packets through UVC extension unit 2 selector 2.
- [samliddicott/meet4k](https://github.com/samliddicott/meet4k): documents OBSBOT selector data as RPC-like state rather than simple write-back memory.

## Safety Model

The tool controls camera state but must not take ownership of the video stream. Zoom, Meet, OBS, and other apps should still use the camera while this tool adjusts supported controls.

The menu app registers only enabled shortcuts from `Resources/remote-button-capture.json`; disabled captures stay in the keymap but are not active. CLI HID commands may require macOS privacy approval when IOHIDManager is used.

## Test Strategy

CI tests stay hardware-free. The project currently uses a no-dependency `obsbot-remote-self-test` executable instead of XCTest so validation works on bare Apple Command Line Tools installs. Test pure logic and command-adjacent parsing there. Hardware validation remains manual until the project has injectable IOKit boundaries.

CI runs on macOS only because the package imports IOKit.

## Future Extraction Points

Keep the package small until hardware behavior is known:

- `HIDRemoteReader` for CLI IOHIDManager matching, seizure, and callbacks;
- `RemoteHotKeyReader` for menu-app global shortcut registration;
- `Keymap` for mapping confirmed HID usage values to camera actions;
- shared command loop that connects decoded buttons to `UVCController` for CLI and menu use;
- compact menu bar popover camera controls for non-remote users;
- Homebrew formula for the CLI/menu runner and a Homebrew cask once there is a signed `.app` bundle.
