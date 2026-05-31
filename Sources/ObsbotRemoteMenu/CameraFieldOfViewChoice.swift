import ObsbotRemoteCore

enum CameraFieldOfViewChoice: String, CaseIterable, Identifiable {
  case wide
  case medium
  case narrow

  var id: String { rawValue }

  var title: String {
    switch self {
    case .wide:
      "Wide"
    case .medium:
      "Medium"
    case .narrow:
      "Narrow"
    }
  }

  var fieldOfView: OBSBOTFieldOfView {
    switch self {
    case .wide:
      .wide
    case .medium:
      .medium
    case .narrow:
      .narrow
    }
  }

  init?(fieldOfView: OBSBOTFieldOfView) {
    switch fieldOfView {
    case .wide:
      self = .wide
    case .medium:
      self = .medium
    case .narrow:
      self = .narrow
    case .unknown:
      return nil
    }
  }
}
