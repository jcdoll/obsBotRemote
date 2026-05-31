import OSLog
import ObsbotRemoteCore

extension CameraControlsViewModel {
  func setHandGestureControls(_ enabled: Bool) {
    guard !handGestureControlsApplying else {
      return
    }
    cameraControlsLogger.notice(
      "Hand gestures requested \(enabled ? "on" : "off", privacy: .public)")
    invalidateReadback()
    let previousValue = lastConfirmedHandGesturesEnabled
    handGesturesEnabled = enabled
    handGestureControlsApplying = true
    runCommand(
      refreshAfterSuccess: false,
      onSuccess: { [weak self] in
        self?.lastConfirmedHandGesturesEnabled = enabled
      },
      onFailure: { [weak self] in
        self?.handGesturesEnabled = previousValue
      },
      onComplete: { [weak self] in
        self?.handGestureControlsApplying = false
      },
      { completion in
        coordinator.setHandGestureControls(enabled: enabled, completion: completion)
      })
  }

  func applyTinyGestureSettings(_ settings: OBSBOTTinyGestureStateSnapshot?) {
    guard let settings else {
      return
    }
    handGesturesEnabled = settings.master
    lastConfirmedHandGesturesEnabled = settings.master
  }

}
