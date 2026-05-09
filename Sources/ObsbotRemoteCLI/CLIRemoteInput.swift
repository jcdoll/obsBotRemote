import Foundation
import ObsbotRemoteControl

func captureInputs(
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

func waitForRemoteInput(
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
