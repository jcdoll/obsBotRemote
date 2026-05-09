# Remote Button Map

Guided capture command:

```bash
swift run obsbot-remote map-buttons
```

This walks the button list, prompts for each button, and writes:

```text
docs/remote-button-capture.json
```

If that JSON already exists, the mapper resumes it and skips completed buttons. Use `--reset` to start a fresh capture file:

```bash
swift run obsbot-remote map-buttons --reset
```

The mapper uses normal listening by default because macOS denied exclusive seizure for the local Terminal-launched process. Remote keypresses may reach the focused app during mapping.

You can still test exclusive capture explicitly:

```bash
swift run obsbot-remote map-buttons --seize
```

Raw capture command:

```bash
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106 --seize
```

If seizure fails or produces no events, retry mapping without seizure:

```bash
swift run obsbot-remote map-buttons --no-seize
```

Or retry raw capture without seizure:

```bash
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106
```

During guided capture, press Return to arm the capture window, then press and release the named remote button. At a prompt, enter `s` to skip, `r` to retry, or `q` to quit and save a partial capture.

The mapper saves after each completed button, so a later crash or termination should still leave the prior captures in `docs/remote-button-capture.json`.

If two seconds is too short, extend the capture window:

```bash
swift run obsbot-remote map-buttons --seconds 4
```

After capture, use the live decoder to verify normal operation without moving the camera:

```bash
swift run obsbot-remote listen
```

The decoder matches live input against `docs/remote-button-capture.json` and prints the dry-run action, for example `Zoom In -> zoom(delta: 10)`.

Use foreground live control when you want the remote to move the camera:

```bash
swift run obsbot-remote control
```

| Button | HID events | Notes |
|---|---|---|
| On/Off |  |  |
| Choose Device 1 |  |  |
| Choose Device 2 |  |  |
| Choose Device 3 |  |  |
| Choose Device 4 |  |  |
| Preset P1 |  |  |
| Preset P2 |  |  |
| Preset P3 |  |  |
| Gimbal Up |  |  |
| Gimbal Down |  |  |
| Gimbal Left |  |  |
| Gimbal Right |  |  |
| Gimbal Reset |  |  |
| Zoom In |  |  |
| Zoom Out |  |  |
| Track |  |  |
| Close-up |  |  |
| Hand Track |  |  |
| Laser / Whiteboard |  | test click, double-click, and hold separately |
| Desk Mode |  |  |
| Hyperlink |  | test click, double-click, and hold separately |
| Page Up |  | test click and hold separately |
| Page Down |  | test click and hold separately |

The first observed sample for a gimbal arrow looked like a keyboard combo:

```text
keyboard.rightArrow down
keyboard.leftAlt down
keyboard.leftControl down
```

That means some camera buttons may be encoded as modifier-plus-key shortcuts rather than unique HID usages.

`On/Off` is decoded as `powerToggle`. The matching camera-side lab command is:

```bash
swift run obsbot-remote camera-power
```

`listen` prints dry-run actions. `control` executes supported camera actions and prints what it did.
Holding a gimbal direction button is handled through the remote's repeated terminal arrow sequence in non-seize mode.
Track, Close-up, Hand Track, and Desk Mode are mapped to OBSBOT AI mode toggles through extension unit 2 selector 6.
