# Hardware Notes

Observed with:

```bash
swift run obsbot-remote devices
```

Observed hardware:

| Device | Vendor ID | Product ID | USB vendor | USB product |
|---|---:|---:|---|---|
| OBSBOT Smart Remote 2 dongle | `0x1106` | `0xB106` | `CY.Ltd` | `OBSBOT Remote` |
| OBSBOT camera | `0x3564` | `0xFF02` | `Remo Tech Co., Ltd.` | `OBSBOT Tiny 3` |

Use the remote ids for HID sniffing:

```bash
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106
```

Add `--seize` when testing exclusive remote capture:

```bash
swift run obsbot-remote hid-sniff --vendor-id 0x1106 --product-id 0xB106 --seize
```

Native UVC camera probe:

```bash
swift run obsbot-remote camera-probe
```

Example probe output:

```text
camera 0x3564:0xFF02
configurationDescriptorLength=752
videoControlInterface number=0 alternate=0 protocol=0
cameraTerminal id=1 interface=0 type=0x0201 controls=zoom-abs, pan-tilt-abs
extensionUnit id=2 interface=0 guid=9a1e7291-6843-4683-6d92-39bc7906ee49 controls=19 selectors=1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
zoomCurrent=0
zoomRange min=0 max=100 res=1 default=0
panTiltCurrent pan=0 tilt=0
panTiltRange min=(pan=-468000, tilt=-324000) max=(pan=468000, tilt=324000) res=(pan=3600, tilt=3600) default=(pan=0, tilt=0)
aiMode=off
```

Observed OBSBOT run status is stored in extension unit 2 selector 6, byte offset 9. The sleep/wake command is sent through extension unit 2 selector 2 as a 60-byte vendor packet.

Observed Tiny-series AI mode status is stored in extension unit 2 selector 6 at byte offsets 24 and 28. The SDK's `cameraSetAiModeU(mode, subMode)` writes selector 6 with a 60-byte payload beginning `16 02 <mode> <subMode>`. Track, Upper, and Close-up all use `AiWorkModeHuman`, but they use different SDK submodes: Track is `AiSubModeNormal` `(2, 0)`, Upper is `AiSubModeUpperBody` `(2, 1)`, and Close-up is `AiSubModeCloseUp` `(2, 2)`. Current remote mappings also use hand tracking `(3, 0)` and desk mode `(5, 0)`. `AiWorkModeSwitching` `(6, 0)` is a transient status while the camera changes AI mode.

Manual Tiny 3 validation: standard UVC `pan-tilt-abs` moves the physical gimbal; a `36_000` unit step is a visible 10-degree nudge. Live remote control currently uses `18_000` for a smaller nudge.

Reference material for the OBSBOT vendor controls:

- [OBSBOT SDK](https://www.obsbot.com/sdk)
- [aaronsb/obsbot-camera-control](https://github.com/aaronsb/obsbot-camera-control)
- [cgevans/tiny2](https://github.com/cgevans/tiny2)
- [samliddicott/meet4k](https://github.com/samliddicott/meet4k)

No-op write validations:

```bash
swift run obsbot-remote camera-zoom --delta 0
swift run obsbot-remote camera-pan-tilt --pan 0 --tilt 0
```

Sleep/wake lab commands:

```bash
swift run obsbot-remote camera-power status
swift run obsbot-remote camera-power
swift run obsbot-remote camera-power on
swift run obsbot-remote camera-power off
```
