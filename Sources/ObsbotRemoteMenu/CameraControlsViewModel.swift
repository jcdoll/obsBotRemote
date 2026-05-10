import Combine
import ObsbotRemoteCore

@MainActor
final class CameraControlsViewModel: ObservableObject {
  @Published var panText = "Pan 0"
  @Published var tiltText = "Tilt 0"
  @Published var zoomText = "Zoom 0"
  @Published var aiModeText = "Unknown"
  @Published var zoomValue = 0.0
  @Published var zoomRange = 0.0...100.0
  @Published var aiModeChoice = CameraAIModeChoice.off
  @Published var panTiltStep: Int {
    didSet {
      coordinator.updatePanTiltStep(Int32(panTiltStep))
    }
  }
  @Published var zoomStep: Int {
    didSet {
      coordinator.updateZoomStep(zoomStep)
    }
  }

  private let coordinator: CameraControlCoordinator
  private let log: @MainActor (String) -> Void
  private var readbackGeneration = 0
  private var panValue: Int32 = 0
  private var tiltValue: Int32 = 0

  init(
    coordinator: CameraControlCoordinator,
    log: @escaping @MainActor (String) -> Void = { _ in }
  ) {
    self.coordinator = coordinator
    self.log = log
    let settings = coordinator.currentSettings()
    panTiltStep = Int(settings.panTiltStep)
    zoomStep = settings.zoomStep
  }

  func loadInitialState() {
    let generation = readbackGeneration

    coordinator.refresh { [weak self] result in
      guard let self else {
        return
      }

      switch result {
      case .success(let snapshot):
        if generation == self.readbackGeneration {
          self.apply(snapshot)
        }
      case .failure(let message):
        self.log("Camera error: \(message)")
      }
    }
  }

  func wake() {
    runCommand(coordinator.wake)
  }

  func sleep() {
    runCommand(coordinator.sleep)
  }

  func center() {
    invalidateReadback()
    applyDisplayedPanTilt(pan: 0, tilt: 0)
    runCommand(coordinator.center)
  }

  func move(_ direction: CameraControlDirection) {
    invalidateReadback()
    applyDisplayedMove(direction)
    runCommand { completion in
      coordinator.move(direction, completion: completion)
    }
  }

  func zoomIn() {
    invalidateReadback()
    let target = displayedZoomTarget(delta: zoomStep)
    applyDisplayedZoom(target)
    runCommand(coordinator.zoomIn)
  }

  func zoomOut() {
    invalidateReadback()
    let target = displayedZoomTarget(delta: -zoomStep)
    applyDisplayedZoom(target)
    runCommand(coordinator.zoomOut)
  }

  func setZoomFromSlider() {
    invalidateReadback()
    let target = Int(zoomValue.rounded())
    applyDisplayedZoom(target)
    runCommand(
      { completion in
        coordinator.setZoom(target, completion: completion)
      }
    )
  }

  func setAIMode(_ choice: CameraAIModeChoice) {
    invalidateReadback()
    aiModeChoice = choice
    aiModeText = choice.title
    runCommand(
      { completion in
        coordinator.setAIMode(choice.mode, completion: completion)
      }
    )
  }

  func setDisplayedZoom(_ value: Double) {
    zoomValue = value
    zoomText = "Zoom \(Int(value.rounded()))"
  }

  private func runCommand(
    _ command: (
      @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
    ) -> Void
  ) {
    command { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let message):
        self.log(message)
      case .failure(let message):
        self.log("Camera error: \(message)")
      }
    }
  }

  private func displayedZoomTarget(delta: Int) -> Int {
    let current = Int(zoomValue.rounded())
    return max(Int(zoomRange.lowerBound), min(current + delta, Int(zoomRange.upperBound)))
  }

  private func applyDisplayedZoom(_ zoom: Int) {
    zoomValue = Double(zoom)
    zoomText = "Zoom \(zoom)"
  }

  private func applyDisplayedMove(_ direction: CameraControlDirection) {
    let step = Int32(panTiltStep)
    switch direction {
    case .up:
      applyDisplayedPanTilt(pan: panValue, tilt: clampedInt32(tiltValue, plus: step))
    case .down:
      applyDisplayedPanTilt(pan: panValue, tilt: clampedInt32(tiltValue, plus: -step))
    case .left:
      applyDisplayedPanTilt(pan: clampedInt32(panValue, plus: -step), tilt: tiltValue)
    case .right:
      applyDisplayedPanTilt(pan: clampedInt32(panValue, plus: step), tilt: tiltValue)
    }
  }

  private func applyDisplayedPanTilt(pan: Int32, tilt: Int32) {
    panValue = pan
    tiltValue = tilt
    panText = "Pan \(pan)"
    tiltText = "Tilt \(tilt)"
  }

  private func invalidateReadback() {
    readbackGeneration += 1
  }

  private func apply(_ snapshot: CameraControlSnapshot) {
    applyDisplayedPanTilt(pan: snapshot.panTilt.pan, tilt: snapshot.panTilt.tilt)
    applyDisplayedZoom(snapshot.zoom)
    zoomValue = Double(snapshot.zoom)
    zoomRange = Double(snapshot.zoomRange.minimum)...Double(snapshot.zoomRange.maximum)
    aiModeText = snapshot.aiMode.userFacingName
    if let choice = CameraAIModeChoice(mode: snapshot.aiMode) {
      aiModeChoice = choice
    }
  }
}

private func clampedInt32(_ value: Int32, plus delta: Int32) -> Int32 {
  Int32(max(Int64(Int32.min), min(Int64(Int32.max), Int64(value) + Int64(delta))))
}
