public struct CameraState: Equatable, Sendable {
  public var pan: Int
  public var tilt: Int
  public var zoom: Int

  public init(pan: Int = 0, tilt: Int = 0, zoom: Int = 100) {
    self.pan = pan
    self.tilt = tilt
    self.zoom = zoom
  }
}

public enum CameraAction: Equatable, Sendable {
  case move(panDelta: Int, tiltDelta: Int)
  case zoom(delta: Int)
  case recallPreset(String)
  case center
}

public struct CameraPreset: Equatable, Sendable {
  public var pan: Int
  public var tilt: Int
  public var zoom: Int

  public init(pan: Int, tilt: Int, zoom: Int) {
    self.pan = pan
    self.tilt = tilt
    self.zoom = zoom
  }
}

public struct CameraActionReducer: Sendable {
  public var presets: [String: CameraPreset]

  public init(presets: [String: CameraPreset] = [:]) {
    self.presets = presets
  }

  public func applying(_ action: CameraAction, to state: CameraState) -> CameraState {
    switch action {
    case .move(let panDelta, let tiltDelta):
      return CameraState(
        pan: state.pan + panDelta,
        tilt: state.tilt + tiltDelta,
        zoom: state.zoom
      )
    case .zoom(let delta):
      return CameraState(
        pan: state.pan,
        tilt: state.tilt,
        zoom: max(0, state.zoom + delta)
      )
    case .recallPreset(let name):
      guard let preset = presets[name] else {
        return state
      }
      return CameraState(pan: preset.pan, tilt: preset.tilt, zoom: preset.zoom)
    case .center:
      return CameraState(pan: 0, tilt: 0, zoom: state.zoom)
    }
  }
}
