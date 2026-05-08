import Foundation
import IOKit.hid
import Darwin
import ObsbotRemoteCore

private func runMain() -> Int32 {
    ignoreRemoteTerminationSignals()
    do {
        try CommandLineTool(arguments: Array(CommandLine.arguments.dropFirst())).run()
        return 0
    } catch let error as CLIError {
        FileHandle.standardError.write(Data((error.message + "\n").utf8))
        return 2
    } catch let error as UVCRequestError {
        FileHandle.standardError.write(Data(("error: \(error.description)\n").utf8))
        return 1
    } catch {
        FileHandle.standardError.write(Data(("error: \(error)\n").utf8))
        return 1
    }
}

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

    private func printHelp() {
        print(
            """
            usage: obsbot-remote <command> [options]

            commands:
              doctor                         Check local runtime assumptions.
              devices                        List USB devices visible through IOKit.
              hid-sniff [options]            Print HID input values from the remote dongle.
              listen [options]               Decode live remote input and print dry-run actions.
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

            listen options:
              --input <path>                 Button capture JSON path.
              --seize / --no-seize           Try exclusive remote capture, default no-seize.
              --window <seconds>             Grouping window after first input, default 0.35.

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

    private func printDoctor() {
        print("swift: \(swiftVersionHint())")
        print("platform: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("iokit: available")
        print("helper dependencies: none")
    }

    private func printDevices() {
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

    private func runHIDSniff(arguments: [String]) throws {
        let options = try HIDSniffOptions.parse(arguments)
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var matching: [String: Any] = [:]
        if let vendorID = options.vendorID {
            matching[kIOHIDVendorIDKey as String] = Int(vendorID)
        }
        if let productID = options.productID {
            matching[kIOHIDProductIDKey as String] = Int(productID)
        }
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let openOptions = options.seize
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)

        let result = IOHIDManagerOpen(manager, openOptions)
        guard result == kIOReturnSuccess else {
            throw CLIError("failed to open HID manager: \(formatHex(UInt32(bitPattern: result)))")
        }

        IOHIDManagerRegisterInputValueCallback(manager, hidValueCallback, nil)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )

        print("listening for HID input; press Ctrl+C to stop")
        CFRunLoopRun()
    }

    private func runListen(arguments: [String]) throws {
        let options = try ListenOptions.parse(arguments)
        let data = try Data(contentsOf: options.input)
        let capture = try JSONDecoder().decode(ButtonMapCapture.self, from: data)
        let matcher = RemoteButtonMatcher(captures: capture.buttons)
        let collector = HIDEventCollector()

        var openOptions = options.seize
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)
        var manager: IOHIDManager? = makeHIDManager(vendorID: options.vendorID, productID: options.productID)
        var result = manager.map { IOHIDManagerOpen($0, openOptions) } ?? kIOReturnError
        if result != kIOReturnSuccess && options.seize {
            writeStandardError(
                "warning: HID seize failed (\(formatHex(UInt32(bitPattern: result)))); falling back to non-seize mode."
            )
            manager = makeHIDManager(vendorID: options.vendorID, productID: options.productID)
            openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
            result = manager.map { IOHIDManagerOpen($0, openOptions) } ?? kIOReturnError
        }
        if result != kIOReturnSuccess {
            writeStandardError(
                "warning: HID manager open failed (\(formatHex(UInt32(bitPattern: result)))); using terminal byte capture only."
            )
            manager = nil
        }

        if let manager {
            IOHIDManagerRegisterInputValueCallback(
                manager,
                hidCollectCallback,
                Unmanaged.passUnretained(collector).toOpaque()
            )
            IOHIDManagerScheduleWithRunLoop(
                manager,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }
        defer {
            if let manager {
                IOHIDManagerUnscheduleFromRunLoop(
                    manager,
                    CFRunLoopGetCurrent(),
                    CFRunLoopMode.defaultMode.rawValue
                )
                IOHIDManagerClose(manager, openOptions)
            }
        }

        print("Live remote decoder")
        print("Loaded \(capture.buttons.count) captured button signature(s) from \(options.input.path).")
        print("Press remote buttons to print dry-run actions; press Ctrl+C to stop.")

        var terminalMode = TerminalRawMode()
        terminalMode.enable()
        defer {
            terminalMode.restore()
        }

        while true {
            guard let input = waitForRemoteInput(
                collector: collector,
                window: options.window
            ) else {
                print("^C")
                return
            }

            switch matcher.match(input) {
            case let .matched(button):
                print("\(button) -> \(dryRunActionDescription(for: button))")
            case let .ambiguous(buttons):
                print("ambiguous \(buttons.joined(separator: " / ")) -> \(dryRunActionDescription(for: buttons[0]))")
            case .unknown:
                print(
                    "unknown input hid=\(hidSignatureDescription(input.hidEvents)) terminal=\(escapedTerminalBytes(input.terminalBytes))"
                )
            }
            fflush(stdout)
        }
    }

    private func runButtonMap(arguments: [String]) throws {
        var options = try ButtonMapOptions.parse(arguments)
        let collector = HIDEventCollector()
        var openOptions = options.seize
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)

        var manager: IOHIDManager? = makeHIDManager(vendorID: options.vendorID, productID: options.productID)
        var result = manager.map { IOHIDManagerOpen($0, openOptions) } ?? kIOReturnError
        if result != kIOReturnSuccess && options.seize {
            writeStandardError(
                "warning: HID seize failed (\(formatHex(UInt32(bitPattern: result)))); falling back to non-seize mode."
            )
            writeStandardError("warning: remote keypresses may reach the focused app during mapping.")
            options.seize = false
            openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
            manager = makeHIDManager(vendorID: options.vendorID, productID: options.productID)
            result = manager.map { IOHIDManagerOpen($0, openOptions) } ?? kIOReturnError
        }
        if result != kIOReturnSuccess {
            writeStandardError(
                "warning: HID manager open failed (\(formatHex(UInt32(bitPattern: result)))); using terminal byte capture only."
            )
            manager = nil
        }

        if let manager {
            IOHIDManagerRegisterInputValueCallback(
                manager,
                hidCollectCallback,
                Unmanaged.passUnretained(collector).toOpaque()
            )
            IOHIDManagerScheduleWithRunLoop(
                manager,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )
        }
        defer {
            if let manager {
                IOHIDManagerUnscheduleFromRunLoop(
                    manager,
                    CFRunLoopGetCurrent(),
                    CFRunLoopMode.defaultMode.rawValue
                )
                IOHIDManagerClose(manager, openOptions)
            }
        }

        print("Interactive button mapping")
        var captures = try loadExistingButtonCaptures(options: options)
        if captures.isEmpty {
            print("Starting new capture file: \(options.output.path)")
        } else {
            print("Resuming \(captures.count) existing capture(s) from \(options.output.path)")
        }
        print("Press Return to arm capture, then press and release the named remote button.")
        print("The capture window closes automatically after \(options.captureSeconds) second(s).")
        print("Commands at a prompt: s = skip, r = retry, q = quit and save partial capture.")

        var terminalMode = TerminalRawMode()
        terminalMode.enable()
        defer {
            terminalMode.restore()
        }
        for (index, button) in remoteButtonNames.enumerated() {
            if let existing = captures.first(where: { $0.button == button }) {
                print("")
                print("[\(index + 1)/\(remoteButtonNames.count)] \(button)")
                print("Already captured; skipping. \(buttonCaptureSummary(existing))")
                continue
            }
            while true {
                print("")
                print("[\(index + 1)/\(remoteButtonNames.count)] \(button)")
                print("Press Return to arm capture, or enter s/r/q: ", terminator: "")
                fflush(stdout)

                let answer = readPromptAnswer().lowercased()

                if answer == "q" {
                    try writeButtonCapture(captures, options: options)
                    return
                }
                if answer == "s" {
                    upsertButtonCapture(
                        ButtonCapture(
                            button: button,
                            events: [],
                            terminalBytes: nil,
                            terminalEscaped: nil,
                            skipped: true
                        ),
                        in: &captures
                    )
                    try writeButtonCapture(captures, options: options, quiet: true)
                    break
                }
                if answer == "r" {
                    continue
                }

                print("Capturing \(button). Press the remote button now...")
                let captured = captureInputs(
                    collector: collector,
                    seconds: options.captureSeconds
                )
                if captured.hidEvents.isEmpty && captured.terminalBytes.isEmpty {
                    print("No HID events captured for \(button). Enter r to retry or s to skip.")
                    continue
                }

                upsertButtonCapture(
                    ButtonCapture(
                        button: button,
                        events: captured.hidEvents,
                        terminalBytes: captured.terminalBytes.isEmpty ? nil : captured.terminalBytes,
                        terminalEscaped: captured.terminalBytes.isEmpty
                            ? nil
                            : escapedTerminalBytes(captured.terminalBytes),
                        skipped: false
                    ),
                    in: &captures
                )
                try writeButtonCapture(captures, options: options, quiet: true)
                print(
                    "Captured \(captured.hidEvents.count) HID event(s), \(captured.terminalBytes.count) terminal byte(s):"
                )
                for event in captured.hidEvents {
                    print("  \(event.name) \(event.state) usagePage=\(event.usagePage) usage=\(event.usage)")
                }
                if !captured.terminalBytes.isEmpty {
                    print("  terminalBytes=\(escapedTerminalBytes(captured.terminalBytes))")
                }
                break
            }
        }

        try writeButtonCapture(captures, options: options)
    }

    private func runCameraProbe(arguments: [String]) throws {
        let options = try CameraOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        let probe = try controller.probe()

        print("camera \(formatHex(UInt32(options.vendorID))):\(formatHex(UInt32(options.productID)))")
        print("configurationDescriptorLength=\(probe.configurationLength)")
        if probe.videoControlInterfaces.isEmpty {
            print("videoControlInterfaces=none")
        } else {
            for interface in probe.videoControlInterfaces {
                print(
                    "videoControlInterface number=\(interface.number) alternate=\(interface.alternateSetting) protocol=\(interface.protocolNumber)"
                )
            }
        }

        if probe.cameraTerminals.isEmpty {
            print("cameraTerminals=none")
        } else {
            for terminal in probe.cameraTerminals {
                let controls = [
                    UVCCameraTerminalControl.zoomAbsolute,
                    UVCCameraTerminalControl.panTiltAbsolute,
                ].filter { terminal.supports($0) }
                    .map(\.displayName)
                    .joined(separator: ", ")
                print(
                    "cameraTerminal id=\(terminal.terminalID) interface=\(terminal.interfaceNumber) type=\(formatHex(UInt32(terminal.terminalType))) controls=\(controls.isEmpty ? "none" : controls)"
                )
            }
        }

        if probe.extensionUnits.isEmpty {
            print("extensionUnits=none")
        } else {
            for unit in probe.extensionUnits {
                let selectors = unit.advertisedSelectors.map(String.init).joined(separator: ",")
                print(
                    "extensionUnit id=\(unit.unitID) interface=\(unit.interfaceNumber) guid=\(unit.guidString) controls=\(unit.numControls) selectors=\(selectors.isEmpty ? "none" : selectors)"
                )
            }
        }

        if let zoom = try? controller.readZoom() {
            print("zoomCurrent=\(zoom)")
        }
        if let panTilt = try? controller.readPanTilt() {
            print("panTiltCurrent pan=\(panTilt.pan) tilt=\(panTilt.tilt)")
        }
    }

    private func runCameraZoom(arguments: [String]) throws {
        let options = try CameraZoomOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)

        if let delta = options.delta {
            let current = try controller.readZoom()
            let next = max(0, current + delta)
            try controller.setZoom(next)
            print("zoom \(current) -> \(next)")
            return
        }

        if let value = options.value {
            try controller.setZoom(value)
            print("zoom set \(value)")
            return
        }

        let current = try controller.readZoom()
        print("zoomCurrent=\(current)")
    }

    private func runCameraPanTilt(arguments: [String]) throws {
        let options = try CameraPanTiltOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        guard let pan = options.pan, let tilt = options.tilt else {
            throw CLIError("camera-pan-tilt requires --pan and --tilt")
        }
        try controller.setPanTilt(pan: pan, tilt: tilt)
        print("panTilt set pan=\(pan) tilt=\(tilt)")
    }

    private func runCameraPower(arguments: [String]) throws {
        let options = try CameraPowerOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)

        switch options.action {
        case .status:
            let status = try controller.readOBSBOTRunStatus()
            print("powerStatus=\(status)")
        case .toggle:
            let result = try controller.toggleOBSBOTRunStatus()
            print("power \(result.previous) -> \(result.next)")
        case .wake:
            let previous = try controller.readOBSBOTRunStatus()
            try controller.setOBSBOTRunStatus(.run)
            print("power \(previous) -> run")
        case .sleep:
            let previous = try controller.readOBSBOTRunStatus()
            try controller.setOBSBOTRunStatus(.sleep)
            print("power \(previous) -> sleep")
        }
    }

    private func runCameraXUGet(arguments: [String]) throws {
        let options = try CameraXUGetOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        guard let unitID = options.unitID else {
            throw CLIError("camera-xu-get requires --unit")
        }
        guard let selector = options.selector else {
            throw CLIError("camera-xu-get requires --selector")
        }

        if let info = try? controller.readExtensionUnitInfo(unitID: unitID, selector: selector) {
            print("info=\(formatByte(info)) \(extensionInfoDescription(info))")
        }
        if options.length == nil, let length = try? controller.readExtensionUnitLength(unitID: unitID, selector: selector) {
            print("length=\(length)")
        }

        let bytes = try controller.readExtensionUnitCurrent(
            unitID: unitID,
            selector: selector,
            length: options.length
        )
        print("value=\(hexBytes(bytes))")
    }

    private func runCameraXUDump(arguments: [String]) throws {
        let options = try CameraXUDumpOptions.parse(arguments)
        let controller = UVCController(vendorID: options.vendorID, productID: options.productID)
        let probe = try controller.probe()

        for unit in probe.extensionUnits {
            print(
                "extensionUnit id=\(unit.unitID) interface=\(unit.interfaceNumber) guid=\(unit.guidString)"
            )
            for selector in unit.advertisedSelectors {
                let infoText: String
                if let info = try? controller.readExtensionUnitInfo(unitID: unit.unitID, selector: selector) {
                    infoText = "\(formatByte(info)) \(extensionInfoDescription(info))"
                } else {
                    infoText = "unreadable"
                }

                let length = try? controller.readExtensionUnitLength(unitID: unit.unitID, selector: selector)
                let lengthText = length.map(String.init) ?? "unknown"
                let valueText: String
                if let length, length <= options.maxLength,
                   let value = try? controller.readExtensionUnitCurrent(
                    unitID: unit.unitID,
                    selector: selector,
                    length: length
                   ) {
                    valueText = hexBytes(value)
                } else {
                    valueText = "not-read"
                }
                print("  selector=\(selector) info=\(infoText) length=\(lengthText) value=\(valueText)")
            }
        }
    }

    private func writeButtonCapture(
        _ captures: [ButtonCapture],
        options: ButtonMapOptions,
        quiet: Bool = false
    ) throws {
        let capture = ButtonMapCapture(
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            vendorID: options.vendorID.map { formatHex($0) },
            productID: options.productID.map { formatHex($0) },
            seize: options.seize,
            buttons: captures
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(capture)
        let output = options.output
        let parent = output.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: output)
        if !quiet {
            print("")
            print("wrote \(output.path)")
        }
    }

    private func loadExistingButtonCaptures(options: ButtonMapOptions) throws -> [ButtonCapture] {
        guard !options.reset else {
            return []
        }
        guard FileManager.default.fileExists(atPath: options.output.path) else {
            return []
        }

        let data = try Data(contentsOf: options.output)
        let existing = try JSONDecoder().decode(ButtonMapCapture.self, from: data)
        guard !existing.buttons.isEmpty else {
            return []
        }

        return existing.buttons
    }

    private func printUVCControlsStatus() {
        print(
            """
            native UVC control transfer support is implemented directly through IOUSBLib.

            lab commands:
              - camera-probe
              - camera-zoom [--value <raw>|--delta <raw>]
              - camera-pan-tilt --pan <raw> --tilt <raw>
              - camera-power [status|on|off]
            """
        )
    }
}

struct HIDSniffOptions {
    var vendorID: UInt32?
    var productID: UInt32?
    var seize: Bool = false

    static func parse(_ arguments: [String]) throws -> HIDSniffOptions {
        var options = HIDSniffOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseInteger(arguments[index])
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseInteger(arguments[index])
            case "--seize":
                options.seize = true
            default:
                throw CLIError("unknown hid-sniff option: \(arguments[index])")
            }
            index += 1
        }
        return options
    }
}

struct ButtonMapOptions {
    var vendorID: UInt32? = 0x1106
    var productID: UInt32? = 0xB106
    var seize: Bool = false
    var output: URL = URL(fileURLWithPath: "docs/remote-button-capture.json")
    var captureSeconds: TimeInterval = 2.0
    var reset: Bool = false

    static func parse(_ arguments: [String]) throws -> ButtonMapOptions {
        var options = ButtonMapOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseInteger(arguments[index])
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseInteger(arguments[index])
            case "--seize":
                options.seize = true
            case "--no-seize":
                options.seize = false
            case "--reset":
                options.reset = true
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--output requires a value")
                }
                options.output = URL(fileURLWithPath: arguments[index])
            case "--seconds":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--seconds requires a value")
                }
                guard let seconds = TimeInterval(arguments[index]), seconds > 0 else {
                    throw CLIError("--seconds must be a positive number")
                }
                options.captureSeconds = seconds
            default:
                throw CLIError("unknown map-buttons option: \(arguments[index])")
            }
            index += 1
        }
        return options
    }
}

struct ListenOptions {
    var vendorID: UInt32? = 0x1106
    var productID: UInt32? = 0xB106
    var seize: Bool = false
    var input: URL = URL(fileURLWithPath: "docs/remote-button-capture.json")
    var window: TimeInterval = 0.35

    static func parse(_ arguments: [String]) throws -> ListenOptions {
        var options = ListenOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseInteger(arguments[index])
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseInteger(arguments[index])
            case "--seize":
                options.seize = true
            case "--no-seize":
                options.seize = false
            case "--input":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--input requires a value")
                }
                options.input = URL(fileURLWithPath: arguments[index])
            case "--window":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--window requires a value")
                }
                guard let window = TimeInterval(arguments[index]), window > 0 else {
                    throw CLIError("--window must be a positive number")
                }
                options.window = window
            default:
                throw CLIError("unknown listen option: \(arguments[index])")
            }
            index += 1
        }
        return options
    }
}

struct CameraOptions {
    var vendorID: UInt16 = 0x3564
    var productID: UInt16 = 0xFF02

    static func parse(_ arguments: [String]) throws -> CameraOptions {
        var options = CameraOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseUInt16(arguments[index], option: "--product-id")
            default:
                throw CLIError("unknown camera option: \(arguments[index])")
            }
            index += 1
        }
        return options
    }
}

struct CameraZoomOptions {
    var vendorID: UInt16 = 0x3564
    var productID: UInt16 = 0xFF02
    var value: Int?
    var delta: Int?

    static func parse(_ arguments: [String]) throws -> CameraZoomOptions {
        var options = CameraZoomOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseUInt16(arguments[index], option: "--product-id")
            case "--value":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--value requires a value")
                }
                options.value = try parseSignedInteger(arguments[index], option: "--value")
            case "--delta":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--delta requires a value")
                }
                options.delta = try parseSignedInteger(arguments[index], option: "--delta")
            default:
                throw CLIError("unknown camera-zoom option: \(arguments[index])")
            }
            index += 1
        }
        if options.value != nil, options.delta != nil {
            throw CLIError("camera-zoom accepts either --value or --delta, not both")
        }
        return options
    }
}

struct CameraPanTiltOptions {
    var vendorID: UInt16 = 0x3564
    var productID: UInt16 = 0xFF02
    var pan: Int32?
    var tilt: Int32?

    static func parse(_ arguments: [String]) throws -> CameraPanTiltOptions {
        var options = CameraPanTiltOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseUInt16(arguments[index], option: "--product-id")
            case "--pan":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--pan requires a value")
                }
                options.pan = try parseInt32(arguments[index], option: "--pan")
            case "--tilt":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--tilt requires a value")
                }
                options.tilt = try parseInt32(arguments[index], option: "--tilt")
            default:
                throw CLIError("unknown camera-pan-tilt option: \(arguments[index])")
            }
            index += 1
        }
        guard options.pan != nil else {
            throw CLIError("camera-pan-tilt requires --pan")
        }
        guard options.tilt != nil else {
            throw CLIError("camera-pan-tilt requires --tilt")
        }
        return options
    }
}

enum CameraPowerAction {
    case toggle
    case status
    case wake
    case sleep
}

struct CameraPowerOptions {
    var vendorID: UInt16 = 0x3564
    var productID: UInt16 = 0xFF02
    var action: CameraPowerAction = .toggle

    static func parse(_ arguments: [String]) throws -> CameraPowerOptions {
        var options = CameraPowerOptions()
        var actionWasSet = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseUInt16(arguments[index], option: "--product-id")
            case "status":
                try setAction(.status, on: &options, actionWasSet: &actionWasSet)
            case "on", "wake", "run":
                try setAction(.wake, on: &options, actionWasSet: &actionWasSet)
            case "off", "sleep":
                try setAction(.sleep, on: &options, actionWasSet: &actionWasSet)
            default:
                throw CLIError("unknown camera-power option: \(arguments[index])")
            }
            index += 1
        }
        return options
    }

    private static func setAction(
        _ action: CameraPowerAction,
        on options: inout CameraPowerOptions,
        actionWasSet: inout Bool
    ) throws {
        guard !actionWasSet else {
            throw CLIError("camera-power accepts one action")
        }
        options.action = action
        actionWasSet = true
    }
}

struct CameraXUGetOptions {
    var vendorID: UInt16 = 0x3564
    var productID: UInt16 = 0xFF02
    var unitID: UInt8?
    var selector: UInt8?
    var length: Int?

    static func parse(_ arguments: [String]) throws -> CameraXUGetOptions {
        var options = CameraXUGetOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseUInt16(arguments[index], option: "--product-id")
            case "--unit":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--unit requires a value")
                }
                options.unitID = try parseUInt8(arguments[index], option: "--unit")
            case "--selector":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--selector requires a value")
                }
                options.selector = try parseUInt8(arguments[index], option: "--selector")
            case "--length":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--length requires a value")
                }
                let length = try parseSignedInteger(arguments[index], option: "--length")
                guard length > 0, length <= Int(UInt16.max) else {
                    throw CLIError("--length must be between 1 and \(UInt16.max)")
                }
                options.length = length
            default:
                throw CLIError("unknown camera-xu-get option: \(arguments[index])")
            }
            index += 1
        }
        return options
    }
}

struct CameraXUDumpOptions {
    var vendorID: UInt16 = 0x3564
    var productID: UInt16 = 0xFF02
    var maxLength: Int = 128

    static func parse(_ arguments: [String]) throws -> CameraXUDumpOptions {
        var options = CameraXUDumpOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--vendor-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--vendor-id requires a value")
                }
                options.vendorID = try parseUInt16(arguments[index], option: "--vendor-id")
            case "--product-id":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--product-id requires a value")
                }
                options.productID = try parseUInt16(arguments[index], option: "--product-id")
            case "--max-length":
                index += 1
                guard index < arguments.count else {
                    throw CLIError("--max-length requires a value")
                }
                let maxLength = try parseSignedInteger(arguments[index], option: "--max-length")
                guard maxLength > 0 else {
                    throw CLIError("--max-length must be positive")
                }
                options.maxLength = maxLength
            default:
                throw CLIError("unknown camera-xu-dump option: \(arguments[index])")
            }
            index += 1
        }
        return options
    }
}

struct ButtonMapCapture: Codable {
    var capturedAt: String
    var vendorID: String?
    var productID: String?
    var seize: Bool
    var buttons: [ButtonCapture]
}

struct ButtonCapture: Codable {
    var button: String
    var events: [HIDEventRecord]
    var terminalBytes: [UInt8]?
    var terminalEscaped: String?
    var skipped: Bool
}

struct HIDEventRecord: Codable {
    var usagePage: UInt32
    var usage: UInt32
    var value: Int
    var state: String
    var name: String
    var timestamp: TimeInterval
}

struct InputCapture {
    var hidEvents: [HIDEventRecord]
    var terminalBytes: [UInt8]
}

final class HIDEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HIDEventRecord] = []

    func append(_ event: HIDEventRecord) {
        lock.withLock {
            events.append(event)
        }
    }

    func reset() {
        lock.withLock {
            events.removeAll()
        }
    }

    func snapshot() -> [HIDEventRecord] {
        lock.withLock {
            events
        }
    }
}

struct HIDUsage: Hashable {
    var usagePage: UInt32
    var usage: UInt32
}

struct HIDSignature: Hashable {
    var usages: [HIDUsage]
}

enum RemoteButtonMatch {
    case matched(String)
    case ambiguous([String])
    case unknown
}

struct RemoteButtonMatcher {
    private var terminalMatches: [[UInt8]: String] = [:]
    private var hidMatches: [HIDSignature: [String]] = [:]

    init(captures: [ButtonCapture]) {
        for capture in captures where !capture.skipped {
            if let terminalBytes = capture.terminalBytes, !terminalBytes.isEmpty {
                terminalMatches[terminalBytes] = capture.button
            }
            let signature = hidSignature(from: capture.events)
            if !signature.usages.isEmpty {
                hidMatches[signature, default: []].append(capture.button)
            }
        }
    }

    func match(_ input: InputCapture) -> RemoteButtonMatch {
        if !input.terminalBytes.isEmpty, let button = terminalMatches[input.terminalBytes] {
            return .matched(button)
        }

        let signature = hidSignature(from: input.hidEvents)
        guard !signature.usages.isEmpty, let buttons = hidMatches[signature], !buttons.isEmpty else {
            return .unknown
        }

        let uniqueButtons = Array(Set(buttons)).sorted()
        if uniqueButtons.count == 1, let button = uniqueButtons.first {
            return .matched(button)
        }
        return .ambiguous(uniqueButtons)
    }
}

private func upsertButtonCapture(_ capture: ButtonCapture, in captures: inout [ButtonCapture]) {
    if let index = captures.firstIndex(where: { $0.button == capture.button }) {
        captures[index] = capture
    } else {
        captures.append(capture)
    }
}

private func buttonCaptureSummary(_ capture: ButtonCapture) -> String {
    if capture.skipped {
        return "(skipped)"
    }
    let terminalCount = capture.terminalBytes?.count ?? 0
    return "(\(capture.events.count) HID event(s), \(terminalCount) terminal byte(s))"
}

private func hidSignature(from events: [HIDEventRecord]) -> HIDSignature {
    let usages = Set(
        events.compactMap { event -> HIDUsage? in
            guard event.state == "down", event.usage != 1 else {
                return nil
            }
            return HIDUsage(usagePage: event.usagePage, usage: event.usage)
        }
    )
    return HIDSignature(
        usages: usages.sorted {
            ($0.usagePage, $0.usage) < ($1.usagePage, $1.usage)
        }
    )
}

private func hidSignatureDescription(_ events: [HIDEventRecord]) -> String {
    let signature = hidSignature(from: events)
    guard !signature.usages.isEmpty else {
        return "none"
    }
    return signature.usages
        .map { "page=\($0.usagePage)/usage=\($0.usage)" }
        .joined(separator: ",")
}

private func dryRunActionDescription(for button: String) -> String {
    let moveStep = 1_800
    let zoomStep = 10

    switch button {
    case "Preset P1":
        return "recallPreset(P1)"
    case "Preset P2":
        return "recallPreset(P2)"
    case "Preset P3":
        return "recallPreset(P3)"
    case "Gimbal Up":
        return "move(panDelta: 0, tiltDelta: \(moveStep))"
    case "Gimbal Down":
        return "move(panDelta: 0, tiltDelta: -\(moveStep))"
    case "Gimbal Left":
        return "move(panDelta: -\(moveStep), tiltDelta: 0)"
    case "Gimbal Right":
        return "move(panDelta: \(moveStep), tiltDelta: 0)"
    case "Gimbal Reset":
        return "center"
    case "Zoom In":
        return "zoom(delta: \(zoomStep))"
    case "Zoom Out":
        return "zoom(delta: -\(zoomStep))"
    case "On/Off":
        return "powerToggle"
    case "Choose Device 1", "Choose Device 2", "Choose Device 3", "Choose Device 4",
         "Laser / Whiteboard click", "Laser / Whiteboard double-click", "Laser / Whiteboard hold",
         "Hyperlink click", "Hyperlink double-click", "Hyperlink hold",
         "Page Up click", "Page Up hold", "Page Down click", "Page Down hold":
        return "ignored"
    default:
        return "unsupported"
    }
}

private func makeHIDManager(vendorID: UInt32?, productID: UInt32?) -> IOHIDManager {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var matching: [String: Any] = [:]
    if let vendorID {
        matching[kIOHIDVendorIDKey as String] = Int(vendorID)
    }
    if let productID {
        matching[kIOHIDProductIDKey as String] = Int(productID)
    }
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    return manager
}

private let remoteButtonNames = [
    "On/Off",
    "Choose Device 1",
    "Choose Device 2",
    "Choose Device 3",
    "Choose Device 4",
    "Preset P1",
    "Preset P2",
    "Preset P3",
    "Gimbal Up",
    "Gimbal Down",
    "Gimbal Left",
    "Gimbal Right",
    "Gimbal Reset",
    "Zoom In",
    "Zoom Out",
    "Track",
    "Close-up",
    "Hand Track",
    "Laser / Whiteboard click",
    "Laser / Whiteboard double-click",
    "Laser / Whiteboard hold",
    "Desk Mode",
    "Hyperlink click",
    "Hyperlink double-click",
    "Hyperlink hold",
    "Page Up click",
    "Page Up hold",
    "Page Down click",
    "Page Down hold",
]

final class CLIError: Error {
    let message: String

    init(_ message: String) {
        self.message = "error: \(message)"
    }
}

private func hidValueCallback(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ value: IOHIDValue
) {
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)
    guard usage != UInt32.max else {
        return
    }
    let state = intValue == 0 ? "up" : "down"
    print(
        "usagePage=\(usagePage) usage=\(usage) value=\(intValue) state=\(state) name=\(hidUsageName(page: usagePage, usage: usage))"
    )
    fflush(stdout)
}

private func hidCollectCallback(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ value: IOHIDValue
) {
    guard let context, let event = makeHIDEventRecord(from: value) else {
        return
    }
    let collector = Unmanaged<HIDEventCollector>.fromOpaque(context).takeUnretainedValue()
    collector.append(event)
}

private func makeHIDEventRecord(from value: IOHIDValue) -> HIDEventRecord? {
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    guard usage != UInt32.max else {
        return nil
    }
    let intValue = IOHIDValueGetIntegerValue(value)
    return HIDEventRecord(
        usagePage: usagePage,
        usage: usage,
        value: intValue,
        state: intValue == 0 ? "up" : "down",
        name: hidUsageName(page: usagePage, usage: usage),
        timestamp: Date().timeIntervalSince1970
    )
}

private func hidUsageName(page: UInt32, usage: UInt32) -> String {
    guard page == 0x07 else {
        return "page\(page).usage\(usage)"
    }
    return keyboardUsageName(usage)
}

private func keyboardUsageName(_ usage: UInt32) -> String {
    switch usage {
    case 0x01: "keyboard.errorRollOver"
    case 0x04...0x1D:
        "keyboard.\(UnicodeScalar(UInt8(ascii: "A") + UInt8(usage - 0x04)))"
    case 0x1E...0x27:
        "keyboard.\(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"][Int(usage - 0x1E)])"
    case 0x28: "keyboard.return"
    case 0x29: "keyboard.escape"
    case 0x2A: "keyboard.delete"
    case 0x2B: "keyboard.tab"
    case 0x2C: "keyboard.space"
    case 0x3A...0x45:
        "keyboard.F\(usage - 0x39)"
    case 0x4A: "keyboard.home"
    case 0x4B: "keyboard.pageUp"
    case 0x4C: "keyboard.deleteForward"
    case 0x4D: "keyboard.end"
    case 0x4E: "keyboard.pageDown"
    case 0x4F: "keyboard.rightArrow"
    case 0x50: "keyboard.leftArrow"
    case 0x51: "keyboard.downArrow"
    case 0x52: "keyboard.upArrow"
    case 0xE0: "keyboard.leftControl"
    case 0xE1: "keyboard.leftShift"
    case 0xE2: "keyboard.leftAlt"
    case 0xE3: "keyboard.leftGUI"
    case 0xE4: "keyboard.rightControl"
    case 0xE5: "keyboard.rightShift"
    case 0xE6: "keyboard.rightAlt"
    case 0xE7: "keyboard.rightGUI"
    default: "keyboard.usage\(usage)"
    }
}

private func swiftVersionHint() -> String {
    #if swift(>=6.0)
        "6.x"
    #else
        "5.x"
    #endif
}

private func writeStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func ignoreRemoteTerminationSignals() {
    signal(SIGTERM, SIG_IGN)
    signal(SIGQUIT, SIG_IGN)
    signal(SIGINFO, SIG_IGN)
}

private func captureInputs(
    collector: HIDEventCollector,
    seconds: TimeInterval
) -> InputCapture {
    collector.reset()
    var terminalBytes: [UInt8] = []
    _ = readAvailableTerminalBytes()

    let end = Date().addingTimeInterval(seconds)
    while true {
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            return InputCapture(hidEvents: collector.snapshot(), terminalBytes: terminalBytes)
        }
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, min(remaining, 0.25), true)
        terminalBytes.append(contentsOf: readAvailableTerminalBytes())
    }
}

private func waitForRemoteInput(
    collector: HIDEventCollector,
    window: TimeInterval
) -> InputCapture? {
    collector.reset()
    _ = readAvailableTerminalBytes()

    var terminalBytes: [UInt8] = []
    while true {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, true)
        let bytes = readAvailableTerminalBytes()
        if bytes.contains(0x03) || bytes.contains(0x04) {
            return nil
        }
        terminalBytes.append(contentsOf: bytes)
        if !collector.snapshot().isEmpty || !terminalBytes.isEmpty {
            break
        }
    }

    let end = Date().addingTimeInterval(window)
    while end.timeIntervalSinceNow > 0 {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, min(end.timeIntervalSinceNow, 0.05), true)
        let bytes = readAvailableTerminalBytes()
        if bytes.contains(0x03) || bytes.contains(0x04) {
            return nil
        }
        terminalBytes.append(contentsOf: bytes)
    }

    return InputCapture(hidEvents: collector.snapshot(), terminalBytes: terminalBytes)
}

private func readPromptAnswer() -> String {
    if isatty(STDIN_FILENO) != 1 {
        return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    _ = readAvailableTerminalBytes()
    var answer = ""

    while true {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, true)
        for byte in readAvailableTerminalBytes() {
            switch byte {
            case 0x03, 0x04:
                print("^C")
                return "q"
            case 0x0A, 0x0D:
                print("")
                return answer.trimmingCharacters(in: .whitespacesAndNewlines)
            case 0x20...0x7E:
                let scalar = UnicodeScalar(byte)
                let character = Character(scalar)
                answer.append(character)
                print(String(character), terminator: "")
                fflush(stdout)
            default:
                continue
            }
        }
    }
}

private struct TerminalRawMode {
    private let fd = STDIN_FILENO
    private var originalTermios = termios()
    private var originalFlags: Int32 = -1
    private var enabled = false

    mutating func enable() {
        guard isatty(fd) == 1 else {
            return
        }
        guard tcgetattr(fd, &originalTermios) == 0 else {
            return
        }
        originalFlags = fcntl(fd, F_GETFL, 0)

        var raw = originalTermios
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        tcsetattr(fd, TCSANOW, &raw)
        if originalFlags >= 0 {
            _ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)
        }
        enabled = true
    }

    mutating func restore() {
        guard enabled else {
            return
        }
        _ = readAvailableTerminalBytes()
        tcsetattr(fd, TCSANOW, &originalTermios)
        if originalFlags >= 0 {
            _ = fcntl(fd, F_SETFL, originalFlags)
        }
        enabled = false
    }
}

private func readAvailableTerminalBytes() -> [UInt8] {
    var out: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 128)
    let bufferCount = buffer.count
    while true {
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            Darwin.read(STDIN_FILENO, rawBuffer.baseAddress, bufferCount)
        }
        if count > 0 {
            out.append(contentsOf: buffer.prefix(count))
        } else {
            return out
        }
    }
}

private func escapedTerminalBytes(_ bytes: [UInt8]) -> String {
    bytes.map { byte in
        switch byte {
        case 0x1B:
            "\\e"
        case 0x0A:
            "\\n"
        case 0x0D:
            "\\r"
        case 0x09:
            "\\t"
        case 0x20...0x7E:
            String(UnicodeScalar(byte))
        default:
            "\\x" + String(byte, radix: 16, uppercase: true)
        }
    }.joined()
}

private func hexBytes(_ bytes: [UInt8]) -> String {
    bytes.map(formatByte).joined(separator: " ")
}

private func formatByte(_ byte: UInt8) -> String {
    let raw = String(byte, radix: 16, uppercase: true)
    return "0x" + String(repeating: "0", count: max(0, 2 - raw.count)) + raw
}

private func extensionInfoDescription(_ info: UInt8) -> String {
    var flags: [String] = []
    if (info & 0x01) != 0 {
        flags.append("GET")
    }
    if (info & 0x02) != 0 {
        flags.append("SET")
    }
    if (info & 0x04) != 0 {
        flags.append("disabled")
    }
    if (info & 0x08) != 0 {
        flags.append("autoupdate")
    }
    return flags.isEmpty ? "(no flags)" : "(\(flags.joined(separator: ",")))"
}

private func parseUInt8(_ text: String, option: String) throws -> UInt8 {
    let value = try parseInteger(text)
    guard let narrowed = UInt8(exactly: value) else {
        throw CLIError("\(option) must fit in 8 bits")
    }
    return narrowed
}

private func parseUInt16(_ text: String, option: String) throws -> UInt16 {
    let value = try parseInteger(text)
    guard let narrowed = UInt16(exactly: value) else {
        throw CLIError("\(option) must fit in 16 bits")
    }
    return narrowed
}

private func parseSignedInteger(_ text: String, option: String) throws -> Int {
    guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw CLIError("\(option) must be an integer")
    }
    return value
}

private func parseInt32(_ text: String, option: String) throws -> Int32 {
    let value = try parseSignedInteger(text, option: option)
    guard let narrowed = Int32(exactly: value) else {
        throw CLIError("\(option) must fit in 32 bits")
    }
    return narrowed
}

exit(runMain())
