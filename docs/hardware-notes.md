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
zoomCurrent=16
panTiltCurrent pan=-7200 tilt=-298800
```

No-op write validations:

```bash
swift run obsbot-remote camera-zoom --delta 0
swift run obsbot-remote camera-pan-tilt --pan -7200 --tilt -298800
```
