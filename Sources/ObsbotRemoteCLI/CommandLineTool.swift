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
