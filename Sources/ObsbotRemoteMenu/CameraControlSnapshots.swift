import ObsbotRemoteCore

struct CameraImageControlsSnapshot: Sendable {
  var brightness: Int?
  var contrast: Int?
  var saturation: Int?
  var whiteBalanceAuto: Bool?
  var whiteBalanceKelvin: Int?
}

struct CameraAdvancedSettingsSnapshot: Sendable {
  var obsbot: OBSBOTCameraSettingsSnapshot?
  var tinyGesture: OBSBOTTinyGestureStateSnapshot?
}
