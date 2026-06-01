import ObsbotRemoteCore

extension CameraControlCoordinator {
  func setImageAdjustment(
    _ adjustment: OBSBOTImageAdjustment,
    value: Int,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      let clamped = OBSBOTRemoteProtocol.clampedImageAdjustmentValue(value)
      try coordinator.controller.setCameraImageAdjustment(adjustment, value: value)
      return "Set \(adjustment) to \(clamped)."
    }
  }

  func setWhiteBalanceAuto(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setCameraWhiteBalance(mode: .auto)
      return "Enabled auto white balance."
    }
  }

  func setWhiteBalanceManual(
    kelvin: Int,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      let clamped = OBSBOTRemoteProtocol.clampedWhiteBalanceKelvin(kelvin)
      try coordinator.controller.setCameraWhiteBalance(mode: .manual, kelvin: kelvin)
      return "Set white balance to \(clamped)K."
    }
  }

  func resetImageControls(
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.resetCameraImageSettings()
      return "Reset image controls."
    }
  }

  func setHDR(
    enabled: Bool,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setOBSBOTHDR(enabled: enabled)
      return enabled ? "Enabled HDR." : "Disabled HDR."
    }
  }

  func setFaceAutoExposure(
    enabled: Bool,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setOBSBOTFaceAutoExposure(enabled: enabled)
      return enabled ? "Enabled face auto exposure." : "Disabled face auto exposure."
    }
  }

  func setFaceAutoFocus(
    enabled: Bool,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setOBSBOTFaceAutoFocus(enabled: enabled)
      return enabled ? "Enabled face auto focus." : "Disabled face auto focus."
    }
  }

  func setFieldOfView(
    _ fieldOfView: OBSBOTFieldOfView,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setOBSBOTFieldOfView(fieldOfView)
      return "Set field of view to \(fieldOfView.userFacingName)."
    }
  }

  func setHandGestureControls(
    enabled: Bool,
    completion: @escaping @MainActor @Sendable (CameraControlCommandResult<String>) -> Void
  ) {
    enqueue(completion: completion) { coordinator in
      try coordinator.controller.setOBSBOTHandGestureControls(enabled: enabled)
      let selector2Writes = OBSBOTTinyGestureCommandPlan.all(
        enabled: enabled,
        startingSequence: 1
      ).count
      let state = enabled ? "on" : "off"
      return "Requested hand gestures \(state) with \(selector2Writes) SDK gesture writes."
    }
  }

  func readImageControlsOnCommandQueue() -> CameraImageControlsSnapshot? {
    controller.readCameraImageControls().map(CameraImageControlsSnapshot.init(readback:))
  }

  func readAdvancedSettingsOnCommandQueue() -> CameraAdvancedSettingsSnapshot {
    CameraAdvancedSettingsSnapshot(
      obsbot: try? controller.readOBSBOTCameraSettings(),
      tinyGesture: try? controller.readOBSBOTTinyGestureState())
  }
}

extension OBSBOTFieldOfView {
  var userFacingName: String {
    switch self {
    case .wide:
      "Wide"
    case .medium:
      "Medium"
    case .narrow:
      "Narrow"
    case .unknown:
      description
    }
  }
}
