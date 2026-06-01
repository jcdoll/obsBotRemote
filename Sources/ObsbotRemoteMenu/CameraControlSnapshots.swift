import ObsbotRemoteCore

struct CameraImageControlsSnapshot: Sendable {
  var brightness: Int?
  var contrast: Int?
  var saturation: Int?
  var whiteBalanceAuto: Bool?
  var whiteBalanceKelvin: Int?

  init(readback: CameraImageControlsReadback) {
    brightness = readback.brightness
    contrast = readback.contrast
    saturation = readback.saturation
    whiteBalanceAuto = readback.whiteBalanceAuto
    whiteBalanceKelvin = readback.whiteBalanceKelvin
  }
}

struct CameraAdvancedSettingsSnapshot: Sendable {
  var obsbot: OBSBOTCameraSettingsSnapshot?
  var tinyGesture: OBSBOTTinyGestureStateSnapshot?
}
