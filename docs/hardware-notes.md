# Hardware Notes

Observed with:

```bash
swift run obsbot-remote devices
```

Current local devices:

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

Observed probe output:

```text
camera 0x3564:0xFF02
configurationDescriptorLength=752
videoControlInterface number=0 alternate=0 protocol=0
cameraTerminal id=1 interface=0 type=0x0201 controls=zoom-abs, pan-tilt-abs
extensionUnit id=2 interface=0 guid=9a1e7291-6843-4683-6d92-39bc7906ee49 controls=19 selectors=1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22
zoomCurrent=16
panTiltCurrent pan=-7200 tilt=-298800
```

Observed OBSBOT run status is stored in extension unit 2 selector 6, byte offset 9. The sleep/wake command is sent through extension unit 2 selector 2 as a 60-byte vendor packet.

Reference material for the OBSBOT vendor controls:

- [OBSBOT SDK](https://www.obsbot.com/sdk)
- [aaronsb/obsbot-camera-control](https://github.com/aaronsb/obsbot-camera-control)
- [cgevans/tiny2](https://github.com/cgevans/tiny2)
- [samliddicott/meet4k](https://github.com/samliddicott/meet4k)

No-op write validations:

```bash
swift run obsbot-remote camera-zoom --delta 0
swift run obsbot-remote camera-pan-tilt --pan -7200 --tilt -298800
```

Sleep/wake lab commands:

```bash
swift run obsbot-remote camera-power status
swift run obsbot-remote camera-power
swift run obsbot-remote camera-power on
swift run obsbot-remote camera-power off
```
