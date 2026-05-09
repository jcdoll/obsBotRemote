import Foundation
import IOKit.hid
import ObsbotRemoteCore

public struct RemoteControlSessionConfiguration {
    public var buttonCaptureURL: URL
    public var vendorID: UInt32
    public var productID: UInt32
    public var inputWindow: TimeInterval
    public var requireSeize: Bool

    public init(
        buttonCaptureURL: URL = defaultRemoteButtonCaptureURL,
        vendorID: UInt32 = defaultRemoteVendorID,
        productID: UInt32 = defaultRemoteProductID,
        inputWindow: TimeInterval = defaultRemoteInputWindow,
        requireSeize: Bool = true
    ) {
        self.buttonCaptureURL = buttonCaptureURL
        self.vendorID = vendorID
        self.productID = productID
        self.inputWindow = inputWindow
        self.requireSeize = requireSeize
    }
}

public enum RemoteControlSessionError: Error, CustomStringConvertible {
    case alreadyRunning
    case hidOpenFailed(code: Int32, seize: Bool)

    public var description: String {
        switch self {
        case .alreadyRunning:
            return "remote control is already running"
        case let .hidOpenFailed(code, seize):
            let access = seize ? "exclusive" : "shared"
            var message = "failed to open remote HID device for \(access) access: \(formatIOReturn(code))"
            if code == kIOReturnNotPrivileged {
                message += " (not privileged; grant Input Monitoring to the app and restart it)"
            }
            return message
        }
    }
}

public final class RemoteControlSession: @unchecked Sendable {
    private let configuration: RemoteControlSessionConfiguration
    private let log: @Sendable (String) -> Void
    private let lock = NSLock()

    private var capture: ButtonMapCapture?
    private var matcher: RemoteButtonMatcher?
    private var controller: UVCController?
    private var collector: HIDEventCollector?
    private var manager: IOHIDManager?
    private var openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var started = false
    private var stopRequested = false

    public init(
        configuration: RemoteControlSessionConfiguration = RemoteControlSessionConfiguration(),
        log: @escaping @Sendable (String) -> Void
    ) {
        self.configuration = configuration
        self.log = log
    }

    public func start() throws {
        try lock.withLock {
            guard !started else {
                throw RemoteControlSessionError.alreadyRunning
            }
            started = true
            stopRequested = false
        }

        do {
            let data = try Data(contentsOf: configuration.buttonCaptureURL)
            let capture = try JSONDecoder().decode(ButtonMapCapture.self, from: data)
            let matcher = RemoteButtonMatcher(captures: capture.buttons)
            let controller = UVCController()
            let collector = HIDEventCollector()
            let manager = makeHIDManager(vendorID: configuration.vendorID, productID: configuration.productID)
            let openOptions = configuration.requireSeize
                ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
                : IOOptionBits(kIOHIDOptionsTypeNone)

            let result = IOHIDManagerOpen(manager, openOptions)
            guard result == kIOReturnSuccess else {
                throw RemoteControlSessionError.hidOpenFailed(code: result, seize: configuration.requireSeize)
            }

            IOHIDManagerRegisterInputValueCallback(
                manager,
                hidCollectCallback,
                Unmanaged.passUnretained(collector).toOpaque()
            )

            lock.withLock {
                self.capture = capture
                self.matcher = matcher
                self.controller = controller
                self.collector = collector
                self.manager = manager
                self.openOptions = openOptions
            }

            log("Live remote control")
            log("Loaded \(capture.buttons.count) captured button signature(s) from \(configuration.buttonCaptureURL.path).")

            let thread = Thread { [weak self] in
                self?.runInputLoop()
            }
            thread.name = "OBSBOT Remote HID Control"
            lock.withLock {
                self.thread = thread
            }
            thread.start()
        } catch {
            lock.withLock {
                started = false
                stopRequested = false
                capture = nil
                matcher = nil
                controller = nil
                collector = nil
                manager = nil
                thread = nil
                runLoop = nil
            }
            throw error
        }
    }

    public func stop() {
        let runLoop = lock.withLock { () -> CFRunLoop? in
            guard started else {
                return nil
            }
            stopRequested = true
            return self.runLoop
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    private func runInputLoop() {
        guard let manager = lock.withLock({ self.manager }) else {
            return
        }

        guard let runLoop = CFRunLoopGetCurrent() else {
            return
        }
        lock.withLock {
            self.runLoop = runLoop
        }
        IOHIDManagerScheduleWithRunLoop(
            manager,
            runLoop,
            CFRunLoopMode.defaultMode.rawValue
        )

        defer {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                runLoop,
                CFRunLoopMode.defaultMode.rawValue
            )
            IOHIDManagerClose(manager, openOptions)
            lock.withLock {
                capture = nil
                matcher = nil
                controller = nil
                collector = nil
                self.manager = nil
                thread = nil
                self.runLoop = nil
                started = false
                stopRequested = false
            }
            log("remote control stopped")
        }

        while !isStopRequested() {
            guard let input = waitForHIDInput() else {
                continue
            }
            handle(input)
        }
    }

    private func waitForHIDInput() -> InputCapture? {
        guard let collector = lock.withLock({ self.collector }) else {
            return nil
        }

        collector.reset()
        while !isStopRequested() {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, true)
            if !collector.snapshot().isEmpty {
                break
            }
        }
        guard !isStopRequested() else {
            return nil
        }

        let end = Date().addingTimeInterval(configuration.inputWindow)
        while !isStopRequested(), end.timeIntervalSinceNow > 0 {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, min(end.timeIntervalSinceNow, 0.05), true)
        }

        let events = collector.snapshot()
        guard !events.isEmpty else {
            return nil
        }
        return InputCapture(hidEvents: events, terminalBytes: [])
    }

    private func handle(_ input: InputCapture) {
        guard let matcher = lock.withLock({ self.matcher }),
              let controller = lock.withLock({ self.controller }) else {
            return
        }

        switch matcher.match(input) {
        case let .matched(button):
            runCameraAction(for: button, controller: controller)
        case let .ambiguous(buttons):
            log("ambiguous \(buttons.joined(separator: " / ")) -> ignored")
        case .unknown:
            if isReleaseOnlyInput(input) {
                return
            }
            log("unknown input hid=\(hidSignatureDescription(input.hidEvents))")
        }
    }

    private func runCameraAction(for button: String, controller: UVCController) {
        do {
            let result = try remoteCameraActionDescription(for: button, controller: controller)
            log("\(button) -> \(result)")
        } catch let error as UVCRequestError {
            log("\(button) -> error: \(error.description)")
        } catch {
            log("\(button) -> error: \(error)")
        }
    }

    private func isStopRequested() -> Bool {
        lock.withLock {
            stopRequested
        }
    }
}

private func formatIOReturn(_ code: Int32) -> String {
    formatHex(UInt32(bitPattern: code), width: 8)
}
