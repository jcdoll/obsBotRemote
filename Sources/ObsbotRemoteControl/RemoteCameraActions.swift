import Foundation
import ObsbotRemoteCore

public struct HeldRemoteInput {
  public var button: String
  public var repeatCount: Int

  public init(button: String, repeatCount: Int) {
    self.button = button
    self.repeatCount = repeatCount
  }
}

public func remoteCameraActionDescription(
  for button: String,
  controller: UVCController
) throws -> String {
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
    return try movePanTilt(
      controller: controller, panDelta: 0, tiltDelta: -defaultRemotePanTiltStep)
  case "Gimbal Left":
    return try movePanTilt(
      controller: controller, panDelta: -defaultRemotePanTiltStep, tiltDelta: 0)
  case "Gimbal Right":
    return try movePanTilt(controller: controller, panDelta: defaultRemotePanTiltStep, tiltDelta: 0)
  case "Gimbal Reset":
    try controller.setPanTilt(pan: 0, tilt: 0)
    return "center"
  case "Track":
    return try toggleAIMode(controller: controller, target: .humanNormal)
  case "Close-up":
    return try toggleAIMode(controller: controller, target: .humanCloseUp)
  case "Hand Track":
    return try toggleAIMode(controller: controller, target: .hand)
  case "Desk Mode":
    return try toggleAIMode(controller: controller, target: .desk)
  case "Choose Device 1", "Choose Device 2", "Choose Device 3", "Choose Device 4",
    "Laser / Whiteboard click", "Laser / Whiteboard double-click", "Laser / Whiteboard hold",
    "Hyperlink click", "Hyperlink double-click", "Hyperlink hold",
    "Page Up click", "Page Up hold", "Page Down click", "Page Down hold":
    return "ignored"
  default:
    return "unsupported"
  }
}

public func heldRemoteInput(from terminalBytes: [UInt8]) -> HeldRemoteInput? {
  let candidates: [(button: String, sequence: [UInt8])] = [
    ("Gimbal Up", [0x1B, 0x1B, 0x5B, 0x41]),
    ("Gimbal Down", [0x1B, 0x1B, 0x5B, 0x42]),
    ("Gimbal Right", [0x1B, 0x1B, 0x5B, 0x43]),
    ("Gimbal Left", [0x1B, 0x1B, 0x5B, 0x44]),
    ("Gimbal Up", [0x1B, 0x5B, 0x41]),
    ("Gimbal Down", [0x1B, 0x5B, 0x42]),
    ("Gimbal Right", [0x1B, 0x5B, 0x43]),
    ("Gimbal Left", [0x1B, 0x5B, 0x44]),
    ("Zoom In", [0x1B, 0x30]),
    ("Zoom Out", [0x1B, 0x06]),
  ]

  for candidate in candidates {
    if let repeatCount = terminalBytes.repeatedCopyCount(of: candidate.sequence) {
      return HeldRemoteInput(button: candidate.button, repeatCount: repeatCount)
    }
  }
  return nil
}

public func isReleaseOnlyInput(_ input: InputCapture) -> Bool {
  input.terminalBytes.isEmpty
    && !input.hidEvents.contains { event in
      event.state == "down" && event.usage != 1
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

private func toggleAIMode(
  controller: UVCController,
  target: OBSBOTAIMode
) throws -> String {
  let result = try controller.toggleOBSBOTAIMode(target)
  return "aiMode \(result.previous) -> \(result.next)"
}

private func clampedInt32(_ value: Int64) -> Int32 {
  Int32(max(Int64(Int32.min), min(Int64(Int32.max), value)))
}

extension [UInt8] {
  fileprivate func repeatedCopyCount(of sequence: [UInt8]) -> Int? {
    guard !isEmpty, !sequence.isEmpty else {
      return nil
    }

    var index = 0
    var repeatCount = 0
    while index + sequence.count <= count {
      for offset in sequence.indices where self[index + offset] != sequence[offset] {
        return nil
      }
      repeatCount += 1
      index += sequence.count
    }

    let remainder = count - index
    if remainder > 0 {
      for offset in 0..<remainder where self[index + offset] != sequence[offset] {
        return nil
      }
    }
    return repeatCount > 0 ? repeatCount : nil
  }
}
