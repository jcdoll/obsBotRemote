import Foundation
import ObsbotRemoteCore

struct CommandLineTool {
  var arguments: [String]

  func run() throws {
    guard let command = arguments.first else {
      printHelp()
      return
    }

    let rest = Array(arguments.dropFirst())
    switch command {
    case "-h", "--help", "help":
      printHelp()
    case "devices":
      printDevices()
    case "doctor":
      printDoctor()
    case "hid-sniff":
      try runHIDSniff(arguments: rest)
    case "control":
      try runControl(arguments: rest)
    case "listen":
      try runListen(arguments: rest)
    case "map-buttons":
      try runButtonMap(arguments: rest)
    case "camera-probe":
      try runCameraProbe(arguments: rest)
    case "camera-zoom":
      try runCameraZoom(arguments: rest)
    case "camera-pan-tilt":
      try runCameraPanTilt(arguments: rest)
    case "camera-power":
      try runCameraPower(arguments: rest)
    case "camera-ai":
      try runCameraAI(arguments: rest)
    case "camera-image":
      try runCameraImage(arguments: rest)
    case "camera-settings":
      try runCameraSettings(arguments: rest)
    case "camera-gesture":
      try runCameraGesture(arguments: rest)
    case "camera-reset":
      try runCameraReset(arguments: rest)
    case "camera-rm-send":
      try runCameraRMSend(arguments: rest)
    case "camera-xu-get":
      try runCameraXUGet(arguments: rest)
    case "camera-xu-dump":
      try runCameraXUDump(arguments: rest)
    case "uvc-controls":
      printUVCControlsStatus()
    default:
      throw CLIError("unknown command: \(command)")
    }
  }

  func printHelp() {
    print(
      """
      usage: obsbot-remote <command> [options]

      commands:
        doctor                         Check local runtime assumptions.
        devices                        List USB devices visible through IOKit.
        hid-sniff [options]            Print HID input values from the remote dongle.
        control                        Run live remote-to-camera control.
        listen                         Decode live remote input and print dry-run actions.
        map-buttons [options]          Prompt through known remote buttons and write JSON.
        camera-probe [options]         Probe native UVC camera controls.
        camera-zoom [options]          Read or set native UVC zoom-abs.
        camera-pan-tilt [options]      Set native UVC pan-tilt-abs.
        camera-power [status|on|off]   Read or toggle OBSBOT sleep/wake state.
        camera-ai [status|mode]        Read or set OBSBOT AI mode.
        camera-image [options]         Show supported ranges or set OBSBOT image controls.
        camera-settings [options]      Read or set OBSBOT camera settings.
        camera-gesture [options]       Set OBSBOT hand gestures; readback is status-only.
        camera-reset [options]         Restore factory settings, recenter, and reboot.
        camera-rm-send [options]       Send one OBSBOT selector-2 RM packet for diagnostics.
        camera-xu-get [options]        Read one UVC extension-unit selector.
        camera-xu-dump [options]       Read advertised UVC extension-unit selectors.
        uvc-controls                   Show native UVC implementation status.

      HID options:
        --vendor-id <id>               Match HID vendor id, decimal or hex.
        --product-id <id>              Match HID product id, decimal or hex.
        --seize                        Ask IOHIDManager to seize the matched device.

      map-buttons options:
        --output <path>                JSON output path.
        --reset                        Start fresh instead of resuming existing JSON.
        --seize                        Try exclusive remote capture.
        --no-seize                     Do not try exclusive remote capture.
        --seconds <seconds>            Capture window per button, default 2.0.

      camera options:
        --vendor-id <id>               Camera USB vendor id, default 0x3564.
        --product-id <id>              Camera USB product id, default 0xFF02.
        --unit <id>                    Extension unit id for camera-xu-get.
        --selector <id>                Extension selector id for camera-xu-get.
        --length <bytes>               Override GET_CUR read length.
        --max-length <bytes>           Max auto-read length for camera-xu-dump.
        --reset                        Reset image controls to neutral.
        --brightness <0-100>           Set OBSBOT brightness.
        --contrast <0-100>             Set OBSBOT contrast.
        --saturation <0-100>           Set OBSBOT saturation.
        --white-balance <kelvin>       Set manual white balance temperature.
        --white-balance-auto <on|off>  Set OBSBOT white balance auto/manual.
        --hdr <on|off>                 Set OBSBOT HDR.
        --face-ae <on|off>             Set OBSBOT face-based auto exposure.
        --face-af <on|off>             Set OBSBOT face-based auto focus.
        --fov <wide|medium|narrow>     Set OBSBOT field of view.
        --mode <mode>                  AI mode: off, track, upper, close-up, hand, desk.
        --gesture-all <on|off>         Set all known Tiny hand gesture switches.
        --hand-gestures <on|off>       Alias for --gesture-all.
        --gesture-master <on|off>      Set Tiny global hand gesture recognition.
        --gesture-target <on|off>      Set Tiny target-selection gesture.
        --gesture-zoom <on|off>        Set Tiny zoom gesture.
        --gesture-dynamic-zoom <on|off> Set Tiny dynamic-zoom gesture.
        --gesture-dynamic-zoom-direction <on|off> Set Tiny dynamic zoom direction.
        --gesture-record <on|off>      Set Tiny record gesture.
        --gesture-auto-frame <on|off>  Set selector-6 auto-frame gesture.
        --gesture-mode <mode>          Set selector-6 auto-frame mode.
        --selector6-gesture-zoom <on|off> Set selector-6 zoom gesture.
        --gesture-zoom-ratio <100-400> Set selector-6 zoom ratio.
        --no-reboot                    Do not reboot after camera-reset.
        --dry-run                      Print Tiny selector-2 packets without USB writes.
        --command-set <id>             Wire command set for camera-rm-send.
        --command-id <id>              Wire command id for camera-rm-send.
        --payload "<bytes>"            Hex or decimal byte list for camera-rm-send.
      """
    )
  }

  func printDoctor() {
    print("swift: \(swiftVersionHint())")
    print("platform: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("iokit: available")
    print("helper dependencies: none")
  }

  func printDevices() {
    let devices = USBDeviceDiscovery().listDevices()
    for device in devices {
      let vid = device.vendorID.map { formatHex(UInt32($0)) } ?? "unknown"
      let pid = device.productID.map { formatHex(UInt32($0)) } ?? "unknown"
      let location = device.locationID.map { formatHex($0, width: 8) } ?? "unknown"
      let name = device.productName ?? "Unnamed USB device"
      let vendor = device.vendorName ?? "Unknown vendor"
      print("\(vid):\(pid) location=\(location) vendor=\"\(vendor)\" product=\"\(name)\"")
    }
  }
}
