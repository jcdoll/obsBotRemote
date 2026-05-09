import Foundation

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

func upsertButtonCapture(_ capture: ButtonCapture, in captures: inout [ButtonCapture]) {
    if let index = captures.firstIndex(where: { $0.button == capture.button }) {
        captures[index] = capture
    } else {
        captures.append(capture)
    }
}

func buttonCaptureSummary(_ capture: ButtonCapture) -> String {
    if capture.skipped {
        return "(skipped)"
    }
    let terminalCount = capture.terminalBytes?.count ?? 0
    return "(\(capture.events.count) HID event(s), \(terminalCount) terminal byte(s))"
}

func hidSignatureDescription(_ events: [HIDEventRecord]) -> String {
    let signature = hidSignature(from: events)
    guard !signature.usages.isEmpty else {
        return "none"
    }
    return signature.usages
        .map { "page=\($0.usagePage)/usage=\($0.usage)" }
        .joined(separator: ",")
}

func dryRunActionDescription(for button: String) -> String {
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

let remoteButtonNames = [
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
