import Foundation
import ObsbotRemoteControl
import ObsbotRemoteCore

struct CameraControlSettings: Equatable, Sendable {
  var panTiltStep: Int32
  var zoomStep: Int

  static let defaultValue = CameraControlSettings(
    panTiltStep: defaultRemotePanTiltStep,
    zoomStep: defaultRemoteZoomStep
  )
}

struct CameraControlPanTilt: Equatable, Sendable {
  var pan: Int32
  var tilt: Int32
}

struct CameraControlSnapshot: Sendable {
  var runStatus: OBSBOTRunStatus
  var aiMode: OBSBOTAIMode
  var zoom: Int
  var zoomRange: UVCZoomRange
  var panTilt: CameraControlPanTilt
}

enum CameraControlDirection: Sendable {
  case up
  case down
  case left
  case right
}

enum CameraControlCommandResult<Value: Sendable>: Sendable {
  case success(Value)
  case failure(String)
}

final class CameraControlCoordinator: @unchecked Sendable {
  let commandQueue = DispatchQueue(label: "OBSBOT Remote Camera Commands")

  private let controller = UVCController()
  private let settingsLock = NSLock()
  private var settings = CameraControlSettings.defaultValue
  private var cachedZoomRange: UVCZoomRange?
  private var cachedPanTiltRange: UVCPanTiltRange?

  func currentSettings() -> CameraControlSettings {
    settingsLock.lock()
    defer { settingsLock.unlock() }
    return settings
  }

  func updatePanTiltStep(_ step: Int32) {
    settingsLock.lock()
    settings.panTiltStep = max(3_600, min(step, 72_000))
    settingsLock.unlock()
  }

  func updateZoomStep(_ step: Int) {
    settingsLock.lock()
    settings.zoomStep = max(1, min(step, 25))
    settingsLock.unlock()
  }

  func performRemoteButtonOnCommandQueue(_ button: String) throws -> String {
    let settings = currentSettings()
    return try remoteCameraActionDescription(
      for: button,
      controller: controller,
      panTiltStep: settings.panTiltStep,
      zoomStep: settings.zoomStep,
      zoomRange: try zoomRangeIfNeededOnCommandQueue(for: button),
      panTiltRange: try panTiltRangeIfNeededOnCommandQueue(for: button)
    )
  }

  func refresh(
    completion:
      @escaping @MainActor @Sendable (
        CameraControlCommandResult<CameraControlSnapshot>
      ) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      let zoomRange = try coordinator.zoomRangeOnCommandQueue()
      let panTilt = try coordinator.controller.readPanTilt()
      return CameraControlSnapshot(
        runStatus: try coordinator.controller.readOBSBOTRunStatus(),
        aiMode: try coordinator.controller.readOBSBOTAIMode(),
        zoom: try coordinator.controller.readZoom(),
        zoomRange: zoomRange,
        panTilt: CameraControlPanTilt(pan: panTilt.pan, tilt: panTilt.tilt)
      )
    }
  }

  func wake(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    setRunStatus(.run, completion: completion)
  }

  func sleep(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    setRunStatus(.sleep, completion: completion)
  }

  func center(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setPanTilt(pan: 0, tilt: 0)
      return "Centered camera."
    }
  }

  func move(
    _ direction: CameraControlDirection,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      let current = try coordinator.controller.readPanTilt()
      let range = try coordinator.panTiltRangeOnCommandQueue()
      let step = coordinator.currentSettings().panTiltStep
      let next: CameraControlPanTilt
      switch direction {
      case .up:
        next = CameraControlPanTilt(
          pan: current.pan,
          tilt: clampedInt32(
            current.tilt, plus: step, minimum: range.minimum.tilt, maximum: range.maximum.tilt)
        )
      case .down:
        next = CameraControlPanTilt(
          pan: current.pan,
          tilt: clampedInt32(
            current.tilt, plus: -step, minimum: range.minimum.tilt, maximum: range.maximum.tilt)
        )
      case .left:
        next = CameraControlPanTilt(
          pan: clampedInt32(
            current.pan, plus: -step, minimum: range.minimum.pan, maximum: range.maximum.pan),
          tilt: current.tilt
        )
      case .right:
        next = CameraControlPanTilt(
          pan: clampedInt32(
            current.pan, plus: step, minimum: range.minimum.pan, maximum: range.maximum.pan),
          tilt: current.tilt
        )
      }
      try coordinator.controller.setPanTilt(pan: next.pan, tilt: next.tilt)
      return "Moved camera \(direction.userFacingName)."
    }
  }

  func zoomIn(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    zoom(deltaSign: 1, completion: completion)
  }

  func zoomOut(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    zoom(deltaSign: -1, completion: completion)
  }

  func setZoom(
    _ zoom: Int,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      let range = try coordinator.zoomRangeOnCommandQueue()
      let next = max(range.minimum, min(zoom, range.maximum))
      try coordinator.controller.setZoom(next)
      return "Set zoom to \(next)."
    }
  }

  func setAIMode(
    _ mode: OBSBOTAIMode,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setOBSBOTAIMode(mode)
      return "Set AI mode to \(mode.userFacingName)."
    }
  }

  private func setRunStatus(
    _ status: OBSBOTRunStatus,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setOBSBOTRunStatus(status)
      return status == .run ? "Woke camera." : "Put camera to sleep."
    }
  }

  private func zoom(
    deltaSign: Int,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      let current = try coordinator.controller.readZoom()
      let range = try coordinator.zoomRangeOnCommandQueue()
      let step = coordinator.currentSettings().zoomStep * deltaSign
      let next = max(range.minimum, min(current + step, range.maximum))
      try coordinator.controller.setZoom(next)
      return deltaSign > 0 ? "Zoomed in." : "Zoomed out."
    }
  }

  private func zoomRangeOnCommandQueue() throws -> UVCZoomRange {
    if let cachedZoomRange {
      return cachedZoomRange
    }
    let range = try controller.readZoomRange()
    cachedZoomRange = range
    return range
  }

  private func panTiltRangeOnCommandQueue() throws -> UVCPanTiltRange {
    if let cachedPanTiltRange {
      return cachedPanTiltRange
    }
    let range = try controller.readPanTiltRange()
    cachedPanTiltRange = range
    return range
  }

  private func zoomRangeIfNeededOnCommandQueue(for button: String) throws -> UVCZoomRange? {
    switch button {
    case "Zoom In", "Zoom Out":
      try zoomRangeOnCommandQueue()
    default:
      nil
    }
  }

  private func panTiltRangeIfNeededOnCommandQueue(for button: String) throws -> UVCPanTiltRange? {
    switch button {
    case "Gimbal Up", "Gimbal Down", "Gimbal Left", "Gimbal Right":
      try panTiltRangeOnCommandQueue()
    default:
      nil
    }
  }

  private func enqueue<Value: Sendable>(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<Value>) -> Void,
    operation: @escaping @Sendable (CameraControlCoordinator) throws -> Value
  ) {
    commandQueue.async { [weak self] in
      guard let self else {
        Task { @MainActor in
          completion(.failure("Camera controller is not available."))
        }
        return
      }

      let result: CameraControlCommandResult<Value>
      do {
        result = .success(try operation(self))
      } catch let error as UVCRequestError {
        result = .failure(error.description)
      } catch {
        result = .failure(String(describing: error))
      }

      Task { @MainActor in
        completion(result)
      }
    }
  }
}

private func clampedInt32(_ value: Int32, plus delta: Int32, minimum: Int32, maximum: Int32)
  -> Int32
{
  let lower = min(minimum, maximum)
  let upper = max(minimum, maximum)
  return Int32(max(Int64(lower), min(Int64(upper), Int64(value) + Int64(delta))))
}

extension CameraControlDirection {
  fileprivate var userFacingName: String {
    switch self {
    case .up:
      "up"
    case .down:
      "down"
    case .left:
      "left"
    case .right:
      "right"
    }
  }
}

extension OBSBOTAIMode {
  var userFacingName: String {
    switch self {
    case .off:
      "Off"
    case .humanNormal:
      "Track"
    case .humanUpperBody:
      "Upper"
    case .humanCloseUp:
      "Close-up"
    case .hand:
      "Hand"
    case .desk:
      "Desk"
    case .switching:
      "Switching"
    case .unknown:
      description
    }
  }
}
