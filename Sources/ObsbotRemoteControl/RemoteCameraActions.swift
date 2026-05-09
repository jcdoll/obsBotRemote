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
  controller: UVCController,
  panTiltStep: Int32 = defaultRemotePanTiltStep,
  zoomStep: Int = defaultRemoteZoomStep,
  zoomRange: UVCZoomRange? = nil,
  panTiltRange: UVCPanTiltRange? = nil
) throws -> String {
  switch button {
  case "On/Off":
    let result = try controller.toggleOBSBOTRunStatus()
    return "power \(result.previous) -> \(result.next)"
  case "Zoom In":
    return try moveZoom(controller: controller, delta: zoomStep, range: zoomRange)
  case "Zoom Out":
    return try moveZoom(controller: controller, delta: -zoomStep, range: zoomRange)
  case "Gimbal Up":
    return try movePanTilt(
      controller: controller, panDelta: 0, tiltDelta: panTiltStep, range: panTiltRange)
  case "Gimbal Down":
    return try movePanTilt(
      controller: controller, panDelta: 0, tiltDelta: -panTiltStep, range: panTiltRange)
  case "Gimbal Left":
    return try movePanTilt(
      controller: controller, panDelta: -panTiltStep, tiltDelta: 0, range: panTiltRange)
  case "Gimbal Right":
    return try movePanTilt(
      controller: controller, panDelta: panTiltStep, tiltDelta: 0, range: panTiltRange)
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
  tiltDelta: Int32,
  range providedRange: UVCPanTiltRange?
) throws -> String {
  let current = try controller.readPanTilt()
  let range = try providedRange ?? controller.readPanTiltRange()
  let nextPan = clampedInt32(
    current.pan,
    plus: panDelta,
    minimum: range.minimum.pan,
    maximum: range.maximum.pan
  )
  let nextTilt = clampedInt32(
    current.tilt,
    plus: tiltDelta,
    minimum: range.minimum.tilt,
    maximum: range.maximum.tilt
  )
  try controller.setPanTilt(pan: nextPan, tilt: nextTilt)
  return "panTilt pan \(current.pan) -> \(nextPan), tilt \(current.tilt) -> \(nextTilt)"
}

private func moveZoom(controller: UVCController, delta: Int, range providedRange: UVCZoomRange?)
  throws -> String
{
  let current = try controller.readZoom()
  let range = try providedRange ?? controller.readZoomRange()
  let next = max(range.minimum, min(current + delta, range.maximum))
  try controller.setZoom(next)
  return "zoom \(current) -> \(next)"
}

private func toggleAIMode(
  controller: UVCController,
  target: OBSBOTAIMode
) throws -> String {
  let result = try controller.toggleOBSBOTAIMode(target)
  return "aiMode \(result.previous) -> \(result.next)"
}

private func clampedInt32(_ value: Int32, plus delta: Int32, minimum: Int32, maximum: Int32)
  -> Int32
{
  let lower = min(minimum, maximum)
  let upper = max(minimum, maximum)
  return Int32(max(Int64(lower), min(Int64(upper), Int64(value) + Int64(delta))))
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
