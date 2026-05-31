import OSLog
import ObsbotRemoteCore

extension CameraControlsViewModel {
  func setHandGestureControls(_ enabled: Bool) {
    cameraControlsLogger.notice(
      "Hand gestures requested \(enabled ? "on" : "off", privacy: .public)")
    invalidateReadback()
    runCommand(
      refreshAfterSuccess: true,
      { completion in
        coordinator.setHandGestureControls(enabled: enabled, completion: completion)
      })
  }

  func applyTinyGestureSettings(_ settings: OBSBOTTinyGestureStateSnapshot?) {
    guard let settings else {
      return
    }
    handGesturesEnabled = settings.master
  }

}
