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
        case "map-buttons":
            try runButtonMap(arguments: rest)
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
              map-buttons [options]          Prompt through known remote buttons and write JSON.
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
            native UVC control transfer support is intentionally not delegated to uvc-util.

            next implementation step:
              - enumerate UVC camera-control interfaces through IOKit;
              - read pan-tilt-abs and zoom-abs control descriptors;
              - send SET_CUR control transfers directly from Swift.
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

exit(runMain())
