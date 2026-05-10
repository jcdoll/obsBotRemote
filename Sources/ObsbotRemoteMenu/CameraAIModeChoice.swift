import ObsbotRemoteCore

enum CameraAIModeChoice: String, CaseIterable, Identifiable {
  case off
  case track
  case upper
  case closeUp
  case hand
  case desk

  var id: String { rawValue }

  var title: String {
    switch self {
    case .off:
      "Off"
    case .track:
      "Track"
    case .upper:
      "Upper"
    case .closeUp:
      "Close-up"
    case .hand:
      "Hand"
    case .desk:
      "Desk"
    }
  }

  var mode: OBSBOTAIMode {
    switch self {
    case .off:
      .off
    case .track:
      .humanNormal
    case .upper:
      .humanUpperBody
    case .closeUp:
      .humanCloseUp
    case .hand:
      .hand
    case .desk:
      .desk
    }
  }

  init?(mode: OBSBOTAIMode) {
    switch mode {
    case .off:
      self = .off
    case .humanNormal:
      self = .track
    case .humanUpperBody:
      self = .upper
    case .humanCloseUp:
      self = .closeUp
    case .hand:
      self = .hand
    case .desk:
      self = .desk
    case .switching, .unknown:
      return nil
    }
  }
}
