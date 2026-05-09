import Foundation
import IOKit.hidsystem
import IOKit.hid

public final class HIDEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HIDEventRecord] = []

    public init() {}

    public func append(_ event: HIDEventRecord) {
        lock.withLock {
            events.append(event)
        }
    }

    public func reset() {
        lock.withLock {
            events.removeAll()
        }
    }

    public func snapshot() -> [HIDEventRecord] {
        lock.withLock {
            events
        }
    }
}

public enum HIDListenAccessStatus: String, Sendable {
    case granted
    case denied
    case unknown
}

public func checkHIDListenAccess() -> HIDListenAccessStatus {
    switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
    case kIOHIDAccessTypeGranted:
        return .granted
    case kIOHIDAccessTypeDenied:
        return .denied
    default:
        return .unknown
    }
}

@discardableResult
public func requestHIDListenAccess() -> Bool {
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
}

public func makeHIDManager(vendorID: UInt32?, productID: UInt32?) -> IOHIDManager {
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

public func hidValueCallback(
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

public func hidCollectCallback(
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

func makeHIDEventRecord(from value: IOHIDValue) -> HIDEventRecord? {
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
