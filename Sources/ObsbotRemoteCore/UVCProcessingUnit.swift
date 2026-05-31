public struct UVCProcessingUnit: Equatable, Sendable {
  public var interfaceNumber: UInt8
  public var unitID: UInt8
  public var sourceID: UInt8
  public var maxMultiplier: UInt16
  public var controls: [UInt8]
  public var processingStringIndex: UInt8

  public init(
    interfaceNumber: UInt8,
    unitID: UInt8,
    sourceID: UInt8,
    maxMultiplier: UInt16,
    controls: [UInt8],
    processingStringIndex: UInt8
  ) {
    self.interfaceNumber = interfaceNumber
    self.unitID = unitID
    self.sourceID = sourceID
    self.maxMultiplier = maxMultiplier
    self.controls = controls
    self.processingStringIndex = processingStringIndex
  }

  public var advertisedControls: [UVCProcessingUnitControl] {
    UVCProcessingUnitControl.allCases.filter { supports($0) }
  }

  public func supports(_ control: UVCProcessingUnitControl) -> Bool {
    let bitIndex = Int(control.rawValue) - 1
    let byteIndex = bitIndex / 8
    guard byteIndex >= 0, byteIndex < controls.count else {
      return false
    }
    return (controls[byteIndex] & UInt8(1 << UInt8(bitIndex % 8))) != 0
  }
}

public enum UVCProcessingUnitControl: UInt8, CaseIterable, Sendable {
  case backlightCompensation = 0x01
  case brightness = 0x02
  case contrast = 0x03
  case gain = 0x04
  case powerLineFrequency = 0x05
  case hue = 0x06
  case saturation = 0x07
  case sharpness = 0x08
  case gamma = 0x09
  case whiteBalanceTemperature = 0x0A
  case whiteBalanceComponent = 0x0B
  case digitalMultiplier = 0x0C
  case digitalMultiplierLimit = 0x0D
  case hueAuto = 0x0E
  case whiteBalanceTemperatureAuto = 0x0F
  case whiteBalanceComponentAuto = 0x10
  case contrastAuto = 0x11

  public static let imageControls: [UVCProcessingUnitControl] = [
    .brightness,
    .contrast,
    .saturation,
    .sharpness,
    .whiteBalanceTemperature,
    .whiteBalanceTemperatureAuto,
    .gain,
    .backlightCompensation,
    .powerLineFrequency,
  ]

  public var displayName: String {
    switch self {
    case .backlightCompensation: "backlight-comp"
    case .brightness: "brightness"
    case .contrast: "contrast"
    case .gain: "gain"
    case .powerLineFrequency: "power-line-frequency"
    case .hue: "hue"
    case .saturation: "saturation"
    case .sharpness: "sharpness"
    case .gamma: "gamma"
    case .whiteBalanceTemperature: "white-balance-temp"
    case .whiteBalanceComponent: "white-balance-component"
    case .digitalMultiplier: "digital-multiplier"
    case .digitalMultiplierLimit: "digital-multiplier-limit"
    case .hueAuto: "hue-auto"
    case .whiteBalanceTemperatureAuto: "white-balance-temp-auto"
    case .whiteBalanceComponentAuto: "white-balance-component-auto"
    case .contrastAuto: "contrast-auto"
    }
  }

  var payloadLength: Int {
    switch self {
    case .powerLineFrequency, .hueAuto, .whiteBalanceTemperatureAuto,
      .whiteBalanceComponentAuto, .contrastAuto:
      1
    case .whiteBalanceComponent:
      4
    default:
      2
    }
  }

  var isScalarLabControl: Bool {
    self != .whiteBalanceComponent
  }

  var isBooleanControl: Bool {
    switch self {
    case .hueAuto, .whiteBalanceTemperatureAuto, .whiteBalanceComponentAuto, .contrastAuto:
      true
    default:
      false
    }
  }

  var isSigned: Bool {
    switch self {
    case .brightness, .hue:
      true
    default:
      false
    }
  }
}
