import Foundation
import IOKit.hid
import ObsbotRemoteCore

extension CommandLineTool {
    func runHIDSniff(arguments: [String]) throws {
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

    func runControl(arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw CLIError("control does not accept options")
        }

        let data = try Data(contentsOf: defaultRemoteButtonCaptureURL)
        let capture = try JSONDecoder().decode(ButtonMapCapture.self, from: data)
        let matcher = RemoteButtonMatcher(captures: capture.buttons)
        let collector = HIDEventCollector()
        let controller = UVCController()

        var openOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
        var manager: IOHIDManager? = makeHIDManager(
            vendorID: defaultRemoteVendorID,
            productID: defaultRemoteProductID
        )
        var result = manager.map { IOHIDManagerOpen($0, openOptions) } ?? kIOReturnError
        if result != kIOReturnSuccess {
            writeStandardError(
                "warning: HID seize failed (\(formatHex(UInt32(bitPattern: result)))); falling back to non-seize mode."
            )
            openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
            manager = makeHIDManager(vendorID: defaultRemoteVendorID, productID: defaultRemoteProductID)
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

        print("Live remote control")
        print("Loaded \(capture.buttons.count) captured button signature(s) from \(defaultRemoteButtonCaptureURL.path).")
        print("Press remote buttons to control the camera; press Ctrl+C to stop.")

        var terminalMode = TerminalRawMode()
        terminalMode.enable()
        defer {
            terminalMode.restore()
        }

        while true {
            guard let input = waitForRemoteInput(
                collector: collector,
                window: defaultRemoteInputWindow
            ) else {
                print("^C")
                return
            }

            switch matcher.match(input) {
            case let .matched(button):
                runCameraAction(for: button, controller: controller)
            case let .ambiguous(buttons):
                print("ambiguous \(buttons.joined(separator: " / ")) -> ignored")
            case .unknown:
                if let heldButton = heldGimbalButton(from: input.terminalBytes) {
                    runCameraAction(for: heldButton, controller: controller)
                } else {
                    print(
                        "unknown input hid=\(hidSignatureDescription(input.hidEvents)) terminal=\(escapedTerminalBytes(input.terminalBytes))"
                    )
                }
            }
            fflush(stdout)
        }
    }

    func runListen(arguments: [String]) throws {
        _ = try ListenOptions.parse(arguments)
        let data = try Data(contentsOf: defaultRemoteButtonCaptureURL)
        let capture = try JSONDecoder().decode(ButtonMapCapture.self, from: data)
        let matcher = RemoteButtonMatcher(captures: capture.buttons)
        let collector = HIDEventCollector()

        let openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
        var manager: IOHIDManager? = makeHIDManager(
            vendorID: defaultRemoteVendorID,
            productID: defaultRemoteProductID
        )
        let result = manager.map { IOHIDManagerOpen($0, openOptions) } ?? kIOReturnError
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
        print("Loaded \(capture.buttons.count) captured button signature(s) from \(defaultRemoteButtonCaptureURL.path).")
        print("Press remote buttons to print dry-run actions; press Ctrl+C to stop.")

        var terminalMode = TerminalRawMode()
        terminalMode.enable()
        defer {
            terminalMode.restore()
        }

        while true {
            guard let input = waitForRemoteInput(
                collector: collector,
                window: defaultRemoteInputWindow
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
                if let heldButton = heldGimbalButton(from: input.terminalBytes) {
                    print("\(heldButton) -> \(dryRunActionDescription(for: heldButton))")
                } else {
                    print(
                        "unknown input hid=\(hidSignatureDescription(input.hidEvents)) terminal=\(escapedTerminalBytes(input.terminalBytes))"
                    )
                }
            }
            fflush(stdout)
        }
    }

    func runButtonMap(arguments: [String]) throws {
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

    func writeButtonCapture(
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

    func loadExistingButtonCaptures(options: ButtonMapOptions) throws -> [ButtonCapture] {
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

    private func runCameraAction(for button: String, controller: UVCController) {
        do {
            let result = try cameraActionDescription(for: button, controller: controller)
            print("\(button) -> \(result)")
        } catch let error as UVCRequestError {
            print("\(button) -> error: \(error.description)")
        } catch {
            print("\(button) -> error: \(error)")
        }
    }

    private func cameraActionDescription(for button: String, controller: UVCController) throws -> String {
        switch button {
        case "On/Off":
            let result = try controller.toggleOBSBOTRunStatus()
            return "power \(result.previous) -> \(result.next)"
        case "Zoom In":
            let current = try controller.readZoom()
            let next = max(0, current + defaultRemoteZoomStep)
            try controller.setZoom(next)
            return "zoom \(current) -> \(next)"
        case "Zoom Out":
            let current = try controller.readZoom()
            let next = max(0, current - defaultRemoteZoomStep)
            try controller.setZoom(next)
            return "zoom \(current) -> \(next)"
        case "Gimbal Up":
            return try movePanTilt(controller: controller, panDelta: 0, tiltDelta: defaultRemotePanTiltStep)
        case "Gimbal Down":
            return try movePanTilt(controller: controller, panDelta: 0, tiltDelta: -defaultRemotePanTiltStep)
        case "Gimbal Left":
            return try movePanTilt(controller: controller, panDelta: -defaultRemotePanTiltStep, tiltDelta: 0)
        case "Gimbal Right":
            return try movePanTilt(controller: controller, panDelta: defaultRemotePanTiltStep, tiltDelta: 0)
        case "Gimbal Reset":
            try controller.setPanTilt(pan: 0, tilt: 0)
            return "center"
        case "Choose Device 1", "Choose Device 2", "Choose Device 3", "Choose Device 4",
             "Laser / Whiteboard click", "Laser / Whiteboard double-click", "Laser / Whiteboard hold",
             "Hyperlink click", "Hyperlink double-click", "Hyperlink hold",
             "Page Up click", "Page Up hold", "Page Down click", "Page Down hold":
            return "ignored"
        default:
            return "unsupported"
        }
    }

    private func movePanTilt(
        controller: UVCController,
        panDelta: Int32,
        tiltDelta: Int32
    ) throws -> String {
        let current = try controller.readPanTilt()
        let nextPan = clampedInt32(Int64(current.pan) + Int64(panDelta))
        let nextTilt = clampedInt32(Int64(current.tilt) + Int64(tiltDelta))
        try controller.setPanTilt(pan: nextPan, tilt: nextTilt)
        return "panTilt pan \(current.pan) -> \(nextPan), tilt \(current.tilt) -> \(nextTilt)"
    }

    private func clampedInt32(_ value: Int64) -> Int32 {
        Int32(max(Int64(Int32.min), min(Int64(Int32.max), value)))
    }
}

private func heldGimbalButton(from terminalBytes: [UInt8]) -> String? {
    let candidates: [(button: String, sequence: [UInt8])] = [
        ("Gimbal Up", [0x1B, 0x1B, 0x5B, 0x41]),
        ("Gimbal Down", [0x1B, 0x1B, 0x5B, 0x42]),
        ("Gimbal Right", [0x1B, 0x1B, 0x5B, 0x43]),
        ("Gimbal Left", [0x1B, 0x1B, 0x5B, 0x44]),
    ]

    return candidates.first { _, sequence in
        terminalBytes.areRepeatedCopies(of: sequence)
    }?.button
}

private extension [UInt8] {
    func areRepeatedCopies(of sequence: [UInt8]) -> Bool {
        guard !isEmpty, !sequence.isEmpty, count % sequence.count == 0 else {
            return false
        }
        for index in indices where self[index] != sequence[index % sequence.count] {
            return false
        }
        return true
    }
}
