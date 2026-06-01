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
  @Published var hdrEnabled = false
  @Published var faceAutoExposureEnabled = false
  @Published var faceAutoFocusEnabled = false
  @Published var fieldOfViewChoice = CameraFieldOfViewChoice.medium
  @Published var handGesturesEnabled = false
  @Published var handGestureControlsApplying = false
  var lastConfirmedHandGesturesEnabled = false
  @Published var brightnessValue = Double(OBSBOTRemoteProtocol.imageAdjustmentRange.defaultValue)
  @Published var brightnessRange = 0.0...100.0
  @Published var brightnessAvailable = true
  @Published var contrastValue = Double(OBSBOTRemoteProtocol.imageAdjustmentRange.defaultValue)
  @Published var contrastRange = 0.0...100.0
  @Published var contrastAvailable = true
  @Published var saturationValue = Double(OBSBOTRemoteProtocol.imageAdjustmentRange.defaultValue)
  @Published var saturationRange = 0.0...100.0
  @Published var saturationAvailable = true
  @Published var whiteBalanceValue = Double(
    OBSBOTRemoteProtocol.whiteBalanceKelvinRange.defaultValue)
  @Published var whiteBalanceRange = 2_000.0...10_000.0
  @Published var whiteBalanceAvailable = true
  @Published var whiteBalanceAuto = true
  @Published var whiteBalanceAutoAvailable = true
  @Published var runStatus: OBSBOTRunStatus?
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

  let coordinator: CameraControlCoordinator
  let log: @MainActor (String) -> Void
  var readbackGeneration = 0
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

  var powerButtonTitle: String {
    switch runStatus {
    case .some(.run):
      "Sleep"
    case .some(.sleep), .some(.privacy):
      "Wake"
    case .some(.unknown), nil:
      "Power"
    }
  }

  var powerButtonSystemImage: String {
    switch runStatus {
    case .some(.run):
      "moon"
    default:
      "power"
    }
  }

  func togglePower() {
    let target: OBSBOTRunStatus
    switch runStatus {
    case .some(.run):
      target = .sleep
    default:
      target = .run
    }

    switch target {
    case .run:
      coordinator.wake { [weak self] result in
        self?.handlePowerResult(result, target: target)
      }
    case .sleep:
      coordinator.sleep { [weak self] result in
        self?.handlePowerResult(result, target: target)
      }
    case .privacy, .unknown:
      log("Camera error: unsupported power target \(target)")
    }
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
      refreshAfterSuccess: true,
      { completion in
        coordinator.setAIMode(choice.mode, completion: completion)
      }
    )
  }

  func setDisplayedZoom(_ value: Double) {
    zoomValue = value
    zoomText = "Zoom \(Int(value.rounded()))"
  }

  func setHDR(_ enabled: Bool) {
    invalidateReadback()
    hdrEnabled = enabled
    runCommand { completion in
      coordinator.setHDR(enabled: enabled, completion: completion)
    }
  }

  func setFaceAutoExposure(_ enabled: Bool) {
    invalidateReadback()
    faceAutoExposureEnabled = enabled
    runCommand { completion in
      coordinator.setFaceAutoExposure(enabled: enabled, completion: completion)
    }
  }

  func setFaceAutoFocus(_ enabled: Bool) {
    invalidateReadback()
    faceAutoFocusEnabled = enabled
    runCommand { completion in
      coordinator.setFaceAutoFocus(enabled: enabled, completion: completion)
    }
  }

  func setFieldOfView(_ choice: CameraFieldOfViewChoice) {
    invalidateReadback()
    fieldOfViewChoice = choice
    runCommand { completion in
      coordinator.setFieldOfView(choice.fieldOfView, completion: completion)
    }
  }

  func setDisplayedBrightness(_ value: Double) {
    brightnessValue = value
  }

  func setBrightnessFromSlider() {
    setImageAdjustment(.brightness, value: Int(brightnessValue.rounded()))
  }

  func setDisplayedContrast(_ value: Double) {
    contrastValue = value
  }

  func setContrastFromSlider() {
    setImageAdjustment(.contrast, value: Int(contrastValue.rounded()))
  }

  func setDisplayedSaturation(_ value: Double) {
    saturationValue = value
  }

  func setSaturationFromSlider() {
    setImageAdjustment(.saturation, value: Int(saturationValue.rounded()))
  }

  func setDisplayedWhiteBalance(_ value: Double) {
    whiteBalanceValue = value
  }

  func setWhiteBalanceFromSlider() {
    invalidateReadback()
    whiteBalanceAuto = false
    runCommand { completion in
      coordinator.setWhiteBalanceManual(
        kelvin: Int(whiteBalanceValue.rounded()),
        completion: completion)
    }
  }

  func setWhiteBalanceAuto(_ enabled: Bool) {
    invalidateReadback()
    whiteBalanceAuto = enabled
    if enabled {
      whiteBalanceValue = Double(OBSBOTRemoteProtocol.whiteBalanceKelvinRange.defaultValue)
      runCommand(coordinator.setWhiteBalanceAuto)
    } else {
      runCommand { completion in
        coordinator.setWhiteBalanceManual(
          kelvin: Int(whiteBalanceValue.rounded()),
          completion: completion)
      }
    }
  }

  func resetImageControls() {
    invalidateReadback()
    brightnessValue = Double(OBSBOTRemoteProtocol.imageAdjustmentRange.defaultValue)
    contrastValue = Double(OBSBOTRemoteProtocol.imageAdjustmentRange.defaultValue)
    saturationValue = Double(OBSBOTRemoteProtocol.imageAdjustmentRange.defaultValue)
    whiteBalanceValue = Double(OBSBOTRemoteProtocol.whiteBalanceKelvinRange.defaultValue)
    whiteBalanceAuto = true
    runCommand(coordinator.resetImageControls)
  }

  private func setImageAdjustment(_ adjustment: OBSBOTImageAdjustment, value: Int) {
    invalidateReadback()
    runCommand { completion in
      coordinator.setImageAdjustment(adjustment, value: value, completion: completion)
    }
  }

  private func handlePowerResult(
    _ result: CameraControlCommandResult<String>,
    target: OBSBOTRunStatus
  ) {
    switch result {
    case .success(let message):
      runStatus = target
      log(message)
    case .failure(let message):
      log("Camera error: \(message)")
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

  private func apply(_ snapshot: CameraControlSnapshot) {
    runStatus = snapshot.runStatus
    applyDisplayedPanTilt(pan: snapshot.panTilt.pan, tilt: snapshot.panTilt.tilt)
    applyDisplayedZoom(snapshot.zoom)
    zoomValue = Double(snapshot.zoom)
    zoomRange = Double(snapshot.zoomRange.minimum)...Double(snapshot.zoomRange.maximum)
    aiModeText = snapshot.aiMode.userFacingName
    if let choice = CameraAIModeChoice(mode: snapshot.aiMode) {
      aiModeChoice = choice
    }
    apply(snapshot.advancedSettings)
    if let imageControls = snapshot.imageControls {
      apply(imageControls)
    }
  }

  private func apply(_ snapshot: CameraAdvancedSettingsSnapshot) {
    if let obsbot = snapshot.obsbot {
      hdrEnabled = obsbot.hdrEnabled
      faceAutoExposureEnabled = obsbot.faceAutoExposureEnabled
      faceAutoFocusEnabled = obsbot.faceAutoFocusEnabled
      if let choice = CameraFieldOfViewChoice(fieldOfView: obsbot.fieldOfView) {
        fieldOfViewChoice = choice
      }
    }
    applyTinyGestureSettings(snapshot.tinyGesture)
  }

  private func apply(_ snapshot: CameraImageControlsSnapshot) {
    if let brightness = snapshot.brightness {
      brightnessValue = Double(brightness)
    }
    if let contrast = snapshot.contrast {
      contrastValue = Double(contrast)
    }
    if let saturation = snapshot.saturation {
      saturationValue = Double(saturation)
    }
    if let whiteBalanceKelvin = snapshot.whiteBalanceKelvin {
      whiteBalanceValue = Double(whiteBalanceKelvin)
    }
    if let whiteBalanceAuto = snapshot.whiteBalanceAuto {
      self.whiteBalanceAuto = whiteBalanceAuto
      if whiteBalanceAuto, snapshot.whiteBalanceKelvin == nil {
        whiteBalanceValue = Double(OBSBOTRemoteProtocol.whiteBalanceKelvinRange.defaultValue)
      }
    }
  }
}

private func clampedInt32(_ value: Int32, plus delta: Int32) -> Int32 {
  Int32(max(Int64(Int32.min), min(Int64(Int32.max), Int64(value) + Int64(delta))))
}
