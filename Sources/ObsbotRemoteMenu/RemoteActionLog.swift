func userFacingActionLog(button: String, result: String) -> String {
  switch button {
  case "On/Off":
    return "On/Off: \(powerActionDescription(from: result))"
  case "Gimbal Up":
    return "Gimbal Up: moved camera up."
  case "Gimbal Down":
    return "Gimbal Down: moved camera down."
  case "Gimbal Left":
    return "Gimbal Left: moved camera left."
  case "Gimbal Right":
    return "Gimbal Right: moved camera right."
  case "Gimbal Reset":
    return "Gimbal Reset: centered camera."
  case "Zoom In":
    return "Zoom In: zoomed in."
  case "Zoom Out":
    return "Zoom Out: zoomed out."
  case "Track":
    return "Track: \(aiModeActionDescription(label: "human tracking", result: result))"
  case "Close-up":
    return "Close-up: \(aiModeActionDescription(label: "close-up tracking", result: result))"
  case "Hand Track":
    return "Hand Track: \(aiModeActionDescription(label: "hand tracking", result: result))"
  case "Desk Mode":
    return "Desk Mode: \(aiModeActionDescription(label: "desk mode", result: result))"
  case "Choose Device 1", "Choose Device 2", "Choose Device 3", "Choose Device 4":
    return "\(button): no camera action assigned."
  default:
    if result == "ignored" {
      return "\(button): ignored."
    }
    if result == "unsupported" {
      return "\(button): unsupported."
    }
    return "\(button): \(result)"
  }
}

func isRepeatableRemoteButton(_ button: String) -> Bool {
  switch button {
  case "Gimbal Up", "Gimbal Down", "Gimbal Left", "Gimbal Right", "Zoom In", "Zoom Out":
    return true
  default:
    return false
  }
}

private func powerActionDescription(from result: String) -> String {
  if result.contains("sleep -> run") {
    return "woke camera."
  }
  if result.contains("run -> sleep") {
    return "put camera to sleep."
  }
  return "toggled camera power."
}

private func aiModeActionDescription(label: String, result: String) -> String {
  if result.hasSuffix(" -> off") {
    return "turned \(label) off."
  }
  return "turned \(label) on."
}
