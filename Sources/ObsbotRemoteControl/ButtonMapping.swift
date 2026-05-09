import Foundation

public let defaultRemoteVendorID: UInt32 = 0x1106
public let defaultRemoteProductID: UInt32 = 0xB106
public let defaultRemoteButtonCaptureURL = URL(fileURLWithPath: "docs/remote-button-capture.json")
public let defaultRemoteInputWindow: TimeInterval = 0.35
public let defaultRemotePanTiltStep: Int32 = 18_000
public let defaultRemoteZoomStep = 10

public struct ButtonMapCapture: Codable {
    public var capturedAt: String
    public var vendorID: String?
    public var productID: String?
    public var seize: Bool
    public var buttons: [ButtonCapture]

    public init(capturedAt: String, vendorID: String?, productID: String?, seize: Bool, buttons: [ButtonCapture]) {
        self.capturedAt = capturedAt
        self.vendorID = vendorID
        self.productID = productID
        self.seize = seize
        self.buttons = buttons
    }
}

public struct ButtonCapture: Codable {
    public var button: String
    public var events: [HIDEventRecord]
    public var terminalBytes: [UInt8]?
    public var terminalEscaped: String?
    public var skipped: Bool

    public init(
        button: String,
        events: [HIDEventRecord],
        terminalBytes: [UInt8]?,
        terminalEscaped: String?,
        skipped: Bool
    ) {
        self.button = button
        self.events = events
        self.terminalBytes = terminalBytes
        self.terminalEscaped = terminalEscaped
        self.skipped = skipped
    }
}

public struct HIDEventRecord: Codable {
    public var usagePage: UInt32
    public var usage: UInt32
    public var value: Int
    public var state: String
    public var name: String
    public var timestamp: TimeInterval

    public init(usagePage: UInt32, usage: UInt32, value: Int, state: String, name: String, timestamp: TimeInterval) {
        self.usagePage = usagePage
        self.usage = usage
        self.value = value
        self.state = state
        self.name = name
        self.timestamp = timestamp
    }
}

public struct InputCapture {
    public var hidEvents: [HIDEventRecord]
    public var terminalBytes: [UInt8]

    public init(hidEvents: [HIDEventRecord], terminalBytes: [UInt8]) {
        self.hidEvents = hidEvents
        self.terminalBytes = terminalBytes
    }
}

public struct HIDUsage: Hashable {
    public var usagePage: UInt32
    public var usage: UInt32

    public init(usagePage: UInt32, usage: UInt32) {
        self.usagePage = usagePage
        self.usage = usage
    }
}

public struct HIDSignature: Hashable {
    public var usages: [HIDUsage]

    public init(usages: [HIDUsage]) {
        self.usages = usages
    }
}

public enum RemoteButtonMatch {
    case matched(String)
    case ambiguous([String])
    case unknown
}

public struct RemoteButtonMatcher {
    private var terminalMatches: [[UInt8]: String] = [:]
    private var hidMatches: [HIDSignature: [String]] = [:]

    public init(captures: [ButtonCapture]) {
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

    public func match(_ input: InputCapture) -> RemoteButtonMatch {
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

public func upsertButtonCapture(_ capture: ButtonCapture, in captures: inout [ButtonCapture]) {
    if let index = captures.firstIndex(where: { $0.button == capture.button }) {
        captures[index] = capture
    } else {
        captures.append(capture)
    }
}

public func buttonCaptureSummary(_ capture: ButtonCapture) -> String {
    if capture.skipped {
        return "(skipped)"
    }
    let terminalCount = capture.terminalBytes?.count ?? 0
    return "(\(capture.events.count) HID event(s), \(terminalCount) terminal byte(s))"
}

public func hidSignatureDescription(_ events: [HIDEventRecord]) -> String {
    let signature = hidSignature(from: events)
    guard !signature.usages.isEmpty else {
        return "none"
    }
    return signature.usages
        .map { "page=\($0.usagePage)/usage=\($0.usage)" }
        .joined(separator: ",")
}

public func dryRunActionDescription(for button: String) -> String {
    switch button {
    case "Preset P1":
        return "recallPreset(P1)"
    case "Preset P2":
        return "recallPreset(P2)"
    case "Preset P3":
        return "recallPreset(P3)"
    case "Gimbal Up":
        return "move(panDelta: 0, tiltDelta: \(defaultRemotePanTiltStep))"
    case "Gimbal Down":
        return "move(panDelta: 0, tiltDelta: -\(defaultRemotePanTiltStep))"
    case "Gimbal Left":
        return "move(panDelta: -\(defaultRemotePanTiltStep), tiltDelta: 0)"
    case "Gimbal Right":
        return "move(panDelta: \(defaultRemotePanTiltStep), tiltDelta: 0)"
    case "Gimbal Reset":
        return "center"
    case "Zoom In":
        return "zoom(delta: \(defaultRemoteZoomStep))"
    case "Zoom Out":
        return "zoom(delta: -\(defaultRemoteZoomStep))"
    case "On/Off":
        return "powerToggle"
    case "Track":
        return "aiModeToggle(humanNormal)"
    case "Close-up":
        return "aiModeToggle(humanCloseUp)"
    case "Hand Track":
        return "aiModeToggle(hand)"
    case "Desk Mode":
        return "aiModeToggle(desk)"
    case "Choose Device 1", "Choose Device 2", "Choose Device 3", "Choose Device 4",
         "Laser / Whiteboard click", "Laser / Whiteboard double-click", "Laser / Whiteboard hold",
         "Hyperlink click", "Hyperlink double-click", "Hyperlink hold",
         "Page Up click", "Page Up hold", "Page Down click", "Page Down hold":
        return "ignored"
    default:
        return "unsupported"
    }
}

public let remoteButtonNames = [
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
