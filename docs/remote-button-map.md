# Remote Button Map

Guided capture command:

```bash
swift run obsbot-remote map-buttons
```

This walks the button list, prompts for each button, and writes:

```text
Resources/remote-button-capture.json
```

If that JSON already exists, the mapper resumes it and skips completed buttons. Use `--reset` to start a fresh capture file:

```bash
swift run obsbot-remote map-buttons --reset
```

The mapper uses normal listening by default because macOS denied exclusive seizure for the local Terminal-launched process. Remote keypresses may reach the focused app during mapping.

Captured buttons include an `enabled` field. Disabled captures stay in the keymap for reference but are ignored by live matching. The menu app registers enabled captures as macOS global hotkeys.

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

The mapper saves after each completed button, so a later crash or termination should still leave the prior captures in `Resources/remote-button-capture.json`.

If two seconds is too short, extend the capture window:

```bash
swift run obsbot-remote map-buttons --seconds 4
```

After capture, use the live decoder to verify normal operation without moving the camera:

```bash
swift run obsbot-remote listen
```

The decoder matches live input against `Resources/remote-button-capture.json` and prints the dry-run action, for example `Zoom In -> zoom(delta: 10)`.

Use foreground live control when you want the remote to move the camera:

```bash
swift run obsbot-remote control
```

| Button | Keystroke | Status |
|---|---|---|
| On/Off | Ctrl+Option+T | enabled |
| Choose Device 1 | Ctrl+Option+- | enabled |
| Choose Device 2 | Ctrl+Option+= | enabled |
| Choose Device 3 | Ctrl+Option+, | enabled |
| Choose Device 4 | Ctrl+Option+. | enabled |
| Preset P1 | Ctrl+Option+Q | enabled |
| Preset P2 | Ctrl+Option+E | enabled |
| Preset P3 | Ctrl+Option+R | enabled |
| Gimbal Up | Ctrl+Option+Up | enabled |
| Gimbal Down | Ctrl+Option+Down | enabled |
| Gimbal Left | Ctrl+Option+Left | enabled |
| Gimbal Right | Ctrl+Option+Right | enabled |
| Gimbal Reset | Ctrl+Option+0 | enabled |
| Zoom In | Ctrl+Option+F | enabled |
| Zoom Out | Ctrl+Option+H | enabled |
| Track | Ctrl+Option+L | enabled |
| Close-up | Ctrl+Option+[ | enabled |
| Hand Track | Ctrl+Option+] | enabled |
| Laser / Whiteboard click | Ctrl+Option+Backslash | disabled |
| Laser / Whiteboard double-click | Ctrl+Option+/ | disabled |
| Laser / Whiteboard hold | repeated Ctrl+Option+Backslash | disabled |
| Desk Mode | Ctrl+Option+; | enabled |
| Hyperlink click | Tab | disabled |
| Hyperlink double-click | Return | disabled |
| Hyperlink hold | Command+Tab | disabled |
| Page Up click | PageDown | disabled |
| Page Up hold | B | disabled |
| Page Down click | PageUp | disabled |
| Page Down hold | PageUp | disabled |

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
Laser / Whiteboard, Hyperlink, and Page Up/Down controls are captured but disabled because they are not part of camera control and can emit presentation keys.
