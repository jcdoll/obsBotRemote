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

Full camera reset is implemented as a long-term recovery path in `camera-reset` and the menu app. The sequence is derived from SDK calls that succeeded on the observed Tiny 3: `aiSetGimbalStop()`, `gimbalRstPosR()`, `cameraSetRestoreFactorySettingsR()`, then `cameraSetPowerCtrlActionR(DevPowerCtrlReboot)`. The corresponding selector-2 packets use SDK-matched route bytes and flags: gimbal stop uses route `0x04`, flag `0x05`, V3 set/id `0x04/0x019C`; Tiny 3 gimbal reset uses route `0x03`, flag `0x25`, V3 set/id `0x03/0x0003`, payload `00 00 00 00 00 00`; factory restore uses route `0x02`, flag `0x25`, V3 set/id `0x02/0x02A0`, payload `01`; reboot uses route `0x02`, flag `0x25`, V3 set/id `0x02/0x0283`, payload `02 00 00 00`.

Observed Tiny-series AI mode status is stored in extension unit 2 selector 6 at byte offsets 24 and 28. The SDK's `cameraSetAiModeU(mode, subMode)` writes selector 6 with a 60-byte payload beginning `16 02 <mode> <subMode>`. Track, Upper, and Close-up all use `AiWorkModeHuman`, but they use different SDK submodes: Track is `AiSubModeNormal` `(2, 0)`, Upper is `AiSubModeUpperBody` `(2, 1)`, and Close-up is `AiSubModeCloseUp` `(2, 2)`. Current remote mappings also use hand tracking `(3, 0)` and desk mode `(5, 0)`. `AiWorkModeSwitching` `(6, 0)` is a transient status while the camera changes AI mode.

`camera-probe` now prints UVC processing-unit descriptors when the camera advertises them. User-facing image controls present OBSBOT-style `0...100` values with `50` as neutral. The UI maps `50` to neutral defaults, so raw defaults such as `128` or `5912` stay neutral without being exposed as slider values. It intentionally does not apply standard UVC current readback on launch because the observed Tiny 3 can report raw/stale maximum values while the live image is still neutral. Brightness, contrast, and saturation have OBSBOT extension unit 2 selector 2 V3 vendor packets using command ids `0x00A7`, `0x00B1`, and `0x00B5`; the current macOS path still does not have a confirmed semantic image readback equivalent for those SDK get calls. White balance must not use the public SDK `cameraSetWhiteBalanceR(DevWhiteBalanceType, int32_t)` path on the observed Tiny 3: the SDK routes that API through standard UVC, returns success, and leaves semantic readback unchanged. The working Tiny 3 macOS white-balance path is the SDK's white-balance settings command pair: legacy command set `0x01`, command ids `0x000A` read and `0x000B` write, converted to V3 selector-2 command set `0x02`, command ids `0x00AA` read and `0x00AB` write. The 28-byte payload is the SDK `WhiteBalanceSetting` layout: `DevWhiteBalanceType` little-endian, Kelvin parameter little-endian, `is_manual_gain`, three bytes of padding, then blue gain, red gain, xab offset, and ygm offset as little-endian 32-bit values. Auto/manual writes first read the current SDK setting and preserve the gain and offset fields; manual only changes mode and Kelvin, while auto only changes mode. The SDK `WhiteBalanceOffset` comments define `xab` and `ygm` as `0(-7) - 56(7)`, so neutral tint is midpoint `28`, not zero. Reset Image explicitly writes brightness, contrast, and saturation to `50`, then writes a neutral auto `WhiteBalanceSetting` with `xab_offset=28` and `ygm_offset=28`. The SDK image-style restore command (`0x02/0x00E1`) returned success on the observed Tiny 3 but did not change a corrupted white-balance setting, so it is not used for Reset Image. Do not reuse V3 command id `0x0081` for white balance; in the SDK command mapping used here, `0x0081` is the gesture-track command.

Reference-derived Tiny-series camera settings are also read from extension unit 2 selector 6: HDR at byte offset 6, face-based auto exposure at byte offset 7, face-based auto focus at byte offset 13, autofocus at byte offset 14, and field of view at byte offset 17. Known write payloads to selector 6 are `01 01 <0|1>` for HDR, `03 01 <0|1>` for face-based auto exposure, and `04 01 <0|1|2>` for wide, medium, or narrow field of view. Face-based auto focus is sent through extension unit 2 selector 2 as a 60-byte V3 vendor packet using camera command `CAM_SET_FACE_FOCUS` mapped to V3 command id `0x00D8`.

The SDK references gesture controls in multiple places. `AiStatus` contains `gesture_target`, `gesture_zoom`, `gesture_dynamic_zoom`, `gesture_record`, `gesture_mirror`, `gesture_snapshot`, `gesture_rolling`, `gesture_zoom_factor`, and `hand_track_type`. The SDK's deprecated `aiSetGestureCtrlR(flag)` still constructs command set `0x03`, command id `0x000D`, with payload `05 <0|1>`, and current SDK individual gesture writes use command set `0x03`: target selection maps to command id `0x0057`, zoom maps to `0x0058`, record maps to `0x0059`, dynamic zoom maps to `0x005B`, and dynamic zoom direction maps to `0x005C`. The legacy packet builder is kept as an SDK-derived low-level helper, while current user-facing gesture controls use SDK individual-control writes where the SDK exposes them.

The newer SDK path is `aiSetGestureParaR(DevGestureParaType, bool)`, mapped to selector 2 command set `0x03`, command id `0x007C`. It sends a five-byte payload: four little-endian bytes for the parameter type, then one `0|1` byte. Relevant boolean parameter types are `0` global gesture function, `1` target selection, `2` zoom, `3` dynamic zoom, `4` record, `5` snapshot, `6` rolling, and `7` mirror/dynamic zoom direction. The SDK also exposes hand-track-specific controls: `aiSetHandTrackGimbalEnabledR(bool)` maps to command set `0x03`, command id `0x0056`, and `aiSetGestureTrackParaR(DevGestureTrackParaType, bool)` maps to command set `0x03`, command id `0x007A`. The macOS "Hand Gestures" switch and `camera-gesture --gesture-all` use SDK Tiny gesture parameters, SDK individual-control writes, hand-track pan/pitch parameters, and hand-track gimbal movement; individual-control writes are sent first, and the master gesture parameter is sent last. When disabling all hand gestures, the app also requests AI mode off so an already-entered tracking mode is not left active. The SDK has separate virtual-track controls (`cameraSetVirtualTrackEnabledR(bool)` and `cameraSetVirtualTrackGestureR(DevVirtualTrackGesture)`) and a broader global AI gate (`aiSetEnabledR(bool)`), but those are not part of the current user-facing hand-gesture switch because they are broader features than a specific Tiny hand-gesture toggle.

The SDK also has a separate selector-6 path named `cameraSetGestureControlU(bool, unsigned char, bool, unsigned short)`, which writes a 60-byte payload beginning `20 05 <auto-frame 0|1> <mode> <zoom 0|1> <ratio-lo> <ratio-hi>` to extension unit 2 selector 6. Status bytes 38 and 39 expose the corresponding bitfield: bit 0 gesture auto-frame, bits 1-2 auto-frame mode (`0` auto-frame, `1` close-up, `2` half body, `3` full body), bit 3 gesture zoom, and bits 4-15 zoom ratio `100...400`. On the observed Tiny 3 this status can read as disabled while the camera still recognizes one-hand/two-hand Tiny gestures, so it must not be treated as the Tiny gesture trigger readback.

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

Full reset recovery:

```bash
swift run obsbot-remote camera-reset
swift run obsbot-remote camera-reset --no-reboot
```

Image and camera-settings lab commands:

```bash
swift run obsbot-remote camera-image
swift run obsbot-remote camera-image --reset
swift run obsbot-remote camera-image --brightness <0-100>
swift run obsbot-remote camera-image --contrast <0-100> --saturation <0-100>
swift run obsbot-remote camera-image --white-balance <kelvin>
swift run obsbot-remote camera-image --white-balance-auto on
swift run obsbot-remote camera-settings
swift run obsbot-remote camera-settings --hdr on
swift run obsbot-remote camera-settings --face-ae on
swift run obsbot-remote camera-settings --face-af on
swift run obsbot-remote camera-settings --fov medium
swift run obsbot-remote camera-ai
swift run obsbot-remote camera-ai off
swift run obsbot-remote camera-gesture
swift run obsbot-remote camera-gesture --gesture-all off --dry-run
swift run obsbot-remote camera-gesture --gesture-all off
swift run obsbot-remote camera-gesture --gesture-master off
swift run obsbot-remote camera-gesture --gesture-target off
swift run obsbot-remote camera-gesture --gesture-zoom off
swift run obsbot-remote camera-gesture --gesture-dynamic-zoom off
swift run obsbot-remote camera-gesture --gesture-dynamic-zoom-direction off
swift run obsbot-remote camera-gesture --gesture-record off
swift run obsbot-remote camera-gesture --gesture-auto-frame off --selector6-gesture-zoom off
swift run obsbot-remote camera-gesture --gesture-mode close-up --gesture-zoom-ratio 200
```
