# OBSBOT Tiny 2 Remote Daemon for macOS

Lightweight daemon that bridges the OBSBOT Smart Remote 2 USB dongle to UVC camera controls, bypassing OBSBOT Center entirely.

## Current Direction

This project has pivoted to a native Swift implementation.

- Python, `pynput`, and uv are not part of the product path.
- `uvc-util` is a useful IOKit reference, but it should not be a required user-installed helper.
- The lab bench should be easy to run from this repo with `swift run obsbot-remote ...`.
- The final product should use IOHIDManager for the remote and direct IOKit UVC control transfers for the camera.

## Background

The OBSBOT Smart Remote 2 is a 2.4GHz HID device that sends keyboard scancodes via a USB dongle. OBSBOT Center intercepts these scancodes and translates them into proprietary camera commands. Without the software running, the remote's camera control buttons do nothing useful.

The goal is to replace OBSBOT Center with a minimal daemon that:

1. Reads HID events from the remote's USB dongle
2. Translates button presses into UVC control transfers
3. Sends those controls directly to the Tiny 2 over USB via IOKit

The camera stays available to Zoom, Meet, OBS, etc. the entire time.

## Key Discovery: uvc-util

[uvc-util](https://github.com/jtfrey/uvc-util) is a macOS CLI tool that sends UVC control transfers using IOKit directly. It does not use libusb and does not detach the kernel video driver. This means you can adjust pan, tilt, zoom, exposure, etc. while the camera is simultaneously streaming to a video conferencing app.

It supports all UVC 1.1 and 1.5 Camera Terminal and Processing Unit controls, including `pan-tilt-abs`, `pan-tilt-rel`, and `zoom-abs`.

Build from source (single gcc invocation, no dependencies beyond Xcode CLI tools):

```bash
git clone https://github.com/jtfrey/uvc-util.git
cd uvc-util/src
gcc -o uvc-util -framework IOKit -framework Foundation \
    uvc-util.m UVCController.m UVCType.m UVCValue.m
cp uvc-util /usr/local/bin/
```

## Why the macOS Kernel Driver Conflict Is a Non-Issue

On macOS, the UVC kernel driver claims the streaming interfaces (for video data). However, UVC camera controls (pan, tilt, zoom, exposure, etc.) are sent as USB control transfers to the Camera Terminal on the control interface. IOKit allows userspace programs to send control transfers without exclusively claiming the device, so there is no conflict with the video stream.

This is fundamentally different from the libusb/pyusb approach, which typically requires `detach_kernel_driver()` and would break the video feed. IOKit sidesteps this entirely.

## Phase 0: Validate UVC Control Support

Before writing any code, confirm the Tiny 2 exposes standard UVC PTZ controls and is not hiding everything behind a vendor-specific extension unit.

```bash
# List all UVC devices
uvc-util --list-devices

# List available controls for the Tiny 2
uvc-util -N "OBSBOT Tiny 2" --list-controls

# Inspect pan-tilt range and step size
uvc-util -N "OBSBOT Tiny 2" -S pan-tilt-abs

# Inspect zoom range
uvc-util -N "OBSBOT Tiny 2" -S zoom-abs

# Test: move the camera
uvc-util -N "OBSBOT Tiny 2" -s pan-tilt-abs="{pan=36000, tilt=0}"
uvc-util -N "OBSBOT Tiny 2" -s pan-tilt-abs=default
```

If `pan-tilt-abs` and `zoom-abs` appear in the control list and the camera physically moves, proceed to Phase 1.

If they do not appear, the Tiny 2 uses vendor-specific extension units. In that case:

- Capture USB traffic from OBSBOT Center using Wireshark with the USBPcap plugin (or on CachyOS with usbmon, which is easier)
- Identify the extension unit ID and control selectors from the captured SET_CUR requests
- Extend `uvc-util` or write a custom IOKit wrapper to send those vendor-specific controls

Alternatively, prototype on the CachyOS Framework Desktop first, where `v4l2-ctl --list-ctrls -d /dev/videoN` will dump all controls (including vendor extensions) immediately.

## Phase 1: Sniff the Remote's HID Keycodes

The dongle presents as a standard HID keyboard. Each button sends one or more keyboard scancodes. The "some keyboard keys stop working" warning in the OBSBOT docs confirms this.

### Option A: pynput (quick and dirty)

```bash
pip install pynput
```

```python
from pynput import keyboard

def on_press(key):
    try:
        print(f"Key: {key.char} (vk={key.vk})")
    except AttributeError:
        print(f"Special: {key} (value={key.value})")

with keyboard.Listener(on_press=on_press) as listener:
    listener.join()
```

Run this, press every button on the remote, record the mapping.

Downside: keypresses still leak into the focused app. You get the same "keyboard interference" that OBSBOT Center causes.

### Option B: IOHIDManager with device seizure (clean)

A small Swift program that opens the dongle's HID device with `kIOHIDOptionsTypeSeizeDevice`, which grabs it exclusively from the keyboard driver. No leaked keypresses, no keyboard interference.

```swift
import Foundation
import IOKit.hid

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))

// Match the OBSBOT dongle by VID/PID (fill in after system_profiler)
let match: [String: Any] = [
    kIOHIDVendorIDKey as String: 0x0000,   // fill in
    kIOHIDProductIDKey as String: 0x0000   // fill in
]
IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))

let callback: IOHIDValueCallback = { context, result, sender, value in
    let element = IOHIDValueGetElement(value)
    let usage = IOHIDElementGetUsage(element)
    let usagePage = IOHIDElementGetUsagePage(element)
    let intValue = IOHIDValueGetIntegerValue(value)
    print("UsagePage: \(usagePage) Usage: \(usage) Value: \(intValue)")
}

IOHIDManagerRegisterInputValueCallback(manager, callback, nil)
CFRunLoopRun()
```

Get the dongle's VID:PID first:

```bash
system_profiler SPUSBDataType | grep -A6 -i obsbot
```

## Phase 2: Build the Keymap

After sniffing, build a table mapping each button to a camera action.

Expected buttons on the Smart Remote 2:

| Button | Expected Action |
|---|---|
| Gimbal Up/Down/Left/Right | pan-tilt-rel or incremental pan-tilt-abs |
| Zoom +/- | zoom-abs increment/decrement |
| Track | toggle AI tracking (may not be UVC-controllable) |
| Hand Track | toggle hand tracking (may not be UVC-controllable) |
| Preset 1/2/3 | recall saved pan-tilt-abs + zoom-abs positions |
| Close-up | may require vendor extension |
| Desk Mode | may require vendor extension |
| Page Up/Down | pass through as real keystrokes (presentation clicker) |
| Laser | hardware, no software needed |

AI features (tracking, hand tracking, close-up, desk mode) are processed on-camera and may not be controllable via UVC at all. If they are only togglable through OBSBOT Center, those buttons would be no-ops in this daemon. Gesture and voice control for those features still work without any software.

## Phase 3: The Daemon

### Python version (simplest)

```python
#!/usr/bin/env python3
"""obsbot-remote-daemon: bridge OBSBOT Smart Remote 2 to UVC controls."""

import subprocess
import json
from pathlib import Path
from pynput import keyboard

CONFIG_PATH = Path("~/.config/obsbot-daemon/config.json").expanduser()
UVC_UTIL = "/usr/local/bin/uvc-util"
DEVICE = "OBSBOT Tiny 2"

# State
current_pan = 0
current_tilt = 0
current_zoom = 100  # query actual value at startup

PAN_STEP = 3600    # arc-seconds per button press (1 degree)
TILT_STEP = 3600
ZOOM_STEP = 10

# Presets: {name: (pan, tilt, zoom)}
presets = {
    "1": (0, 0, 100),
    "2": (36000, 0, 200),
    "3": (-36000, -18000, 150),
}

def uvc_set(control, value):
    subprocess.run(
        [UVC_UTIL, "-N", DEVICE, "-s", f"{control}={value}"],
        capture_output=True,
    )

def uvc_get(control):
    result = subprocess.run(
        [UVC_UTIL, "-N", DEVICE, "-o", control],
        capture_output=True, text=True,
    )
    return result.stdout.strip()

def move(dpan, dtilt):
    global current_pan, current_tilt
    current_pan += dpan
    current_tilt += dtilt
    uvc_set("pan-tilt-abs", f"{{{current_pan},{current_tilt}}}")

def zoom(dz):
    global current_zoom
    current_zoom += dz
    uvc_set("zoom-abs", str(current_zoom))

def recall_preset(name):
    global current_pan, current_tilt, current_zoom
    p = presets.get(name)
    if p:
        current_pan, current_tilt, current_zoom = p
        uvc_set("pan-tilt-abs", f"{{{current_pan},{current_tilt}}}")
        uvc_set("zoom-abs", str(current_zoom))

# Fill in actual keycodes after Phase 1 sniffing
KEYMAP = {
    # keyboard.KeyCode.from_vk(0x??): lambda: move(0, -TILT_STEP),      # up
    # keyboard.KeyCode.from_vk(0x??): lambda: move(0, TILT_STEP),       # down
    # keyboard.KeyCode.from_vk(0x??): lambda: move(-PAN_STEP, 0),       # left
    # keyboard.KeyCode.from_vk(0x??): lambda: move(PAN_STEP, 0),        # right
    # keyboard.KeyCode.from_vk(0x??): lambda: zoom(ZOOM_STEP),          # zoom+
    # keyboard.KeyCode.from_vk(0x??): lambda: zoom(-ZOOM_STEP),         # zoom-
    # keyboard.KeyCode.from_vk(0x??): lambda: recall_preset("1"),       # preset 1
    # keyboard.KeyCode.from_vk(0x??): lambda: recall_preset("2"),       # preset 2
    # keyboard.KeyCode.from_vk(0x??): lambda: recall_preset("3"),       # preset 3
}

def on_press(key):
    action = KEYMAP.get(key)
    if action:
        action()

def main():
    global current_pan, current_tilt, current_zoom
    # Sync state with camera at startup
    # Parse uvc_get output to initialize current values
    print(f"obsbot-remote-daemon started, device: {DEVICE}")
    with keyboard.Listener(on_press=on_press) as listener:
        listener.join()

if __name__ == "__main__":
    main()
```

### Swift version (preferred for production)

A Swift version using IOHIDManager (device seizure, no leaked keypresses) and direct IOKit USB control transfers (no uvc-util dependency) would be cleaner for daily use. This is a larger effort but eliminates the Python dependency, the pynput keystroke leaking problem, and the subprocess overhead per button press.

Rough structure:

- `HIDRemoteReader.swift`: IOHIDManager with `kIOHIDOptionsTypeSeizeDevice`, callback dispatches to keymap
- `UVCController.swift`: IOKit USB control transfers for pan-tilt-abs, zoom-abs (port the relevant parts of uvc-util)
- `main.swift`: glue, config loading, preset management
- Build with `swift build`, run as a LaunchAgent

## Phase 4: Run as a LaunchAgent

Create `~/Library/LaunchAgents/com.vonk.obsbot-daemon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vonk.obsbot-daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/obsbot-remote-daemon</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/obsbot-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/obsbot-daemon.err</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.vonk.obsbot-daemon.plist
```

## Risks and Open Questions

| Risk | Impact | Mitigation |
|---|---|---|
| Tiny 2 does not expose standard UVC PTZ controls | Blocks the entire approach | Run `uvc-util --list-controls` in Phase 0. Fall back to USB traffic capture if needed. |
| AI features (tracking, desk mode) not controllable via UVC | Those remote buttons become no-ops | Use gesture/voice control for AI features; they work without any software. |
| HID seizure requires Input Monitoring permission on macOS | One-time user prompt | Expected; OBSBOT Center requires the same permission. |
| Pan-tilt-abs step size or range differs from remote's expected behavior | Camera movement feels wrong | Query GET_MIN/GET_MAX/GET_RES at startup, scale accordingly. |
| uvc-util subprocess latency for rapid button presses | Sluggish gimbal control | Acceptable for Python prototype. Swift version with direct IOKit calls eliminates this. |
| macOS Sequoia/Tahoe tightens IOKit USB access | May break in future OS updates | Monitor Apple developer docs. DriverKit is the long-term blessed path. |

## Recommended Execution Order

1. Build uvc-util, run `--list-controls` against the Tiny 2 (5 minutes, answers the biggest unknown)
2. If PTZ controls are present, sniff the remote's keycodes with pynput (15 minutes)
3. Build the Python prototype with pynput + uvc-util subprocess calls (1-2 hours)
4. Test end-to-end: remote button press moves camera while Zoom is streaming
5. Optionally port to Swift for a clean LaunchAgent with HID seizure and direct IOKit calls
