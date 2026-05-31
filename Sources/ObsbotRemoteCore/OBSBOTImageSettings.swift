public enum OBSBOTImageAdjustment: CaseIterable, Sendable, CustomStringConvertible {
  case brightness
  case contrast
  case saturation

  var v3CommandID: UInt16 {
    switch self {
    case .brightness:
      0x00A7
    case .contrast:
      0x00B1
    case .saturation:
      0x00B5
    }
  }

  var processingUnitControl: UVCProcessingUnitControl {
    switch self {
    case .brightness:
      .brightness
    case .contrast:
      .contrast
    case .saturation:
      .saturation
    }
  }

  public var description: String {
    switch self {
    case .brightness:
      "brightness"
    case .contrast:
      "contrast"
    case .saturation:
      "saturation"
    }
  }
}

public enum OBSBOTWhiteBalanceMode: UInt32, Sendable, CustomStringConvertible {
  case auto = 0
  case manual = 255

  public var description: String {
    switch self {
    case .auto:
      "auto"
    case .manual:
      "manual"
    }
  }
}

public struct CameraImageControlsReadback: Equatable, Sendable {
  public var brightness: Int?
  public var contrast: Int?
  public var saturation: Int?
  public var whiteBalanceAuto: Bool?
  public var whiteBalanceKelvin: Int?

  public var hasValues: Bool {
    brightness != nil || contrast != nil || saturation != nil || whiteBalanceAuto != nil
      || whiteBalanceKelvin != nil
  }
}

extension OBSBOTRemoteProtocol {
  public static let imageAdjustmentRange = UVCScalarRange(
    minimum: 0,
    maximum: 100,
    resolution: 1,
    defaultValue: 50
  )
  public static let whiteBalanceKelvinRange = UVCScalarRange(
    minimum: 2_000,
    maximum: 10_000,
    resolution: 100,
    defaultValue: 5_000
  )

  public static func makeImageAdjustmentPacket(
    _ adjustment: OBSBOTImageAdjustment,
    value: Int,
    sequence: UInt16
  ) -> [UInt8] {
    makeRMCommandPacket(
      v3CommandID: adjustment.v3CommandID,
      payload: makeUInt32Payload(UInt32(clampedImageAdjustmentValue(value))),
      sequence: sequence
    )
  }

  public static func clampedImageAdjustmentValue(_ value: Int) -> Int {
    max(imageAdjustmentRange.minimum, min(value, imageAdjustmentRange.maximum))
  }

  public static func clampedWhiteBalanceKelvin(_ kelvin: Int) -> Int {
    max(whiteBalanceKelvinRange.minimum, min(kelvin, whiteBalanceKelvinRange.maximum))
  }

  public static func imageAdjustmentRawValue(_ value: Int, range: UVCScalarRange) -> Int {
    let percent = clampedImageAdjustmentValue(value)
    let lower = min(range.minimum, range.maximum)
    let upper = max(range.minimum, range.maximum)
    let neutral = max(lower, min(range.defaultValue, upper))
    guard lower < upper else {
      return lower
    }
    if percent == imageAdjustmentRange.defaultValue {
      return neutral
    }
    if percent < imageAdjustmentRange.defaultValue {
      return interpolatedRawValue(
        percent: percent,
        percentLower: imageAdjustmentRange.minimum,
        percentUpper: imageAdjustmentRange.defaultValue,
        rawLower: lower,
        rawUpper: neutral)
    }
    return interpolatedRawValue(
      percent: percent,
      percentLower: imageAdjustmentRange.defaultValue,
      percentUpper: imageAdjustmentRange.maximum,
      rawLower: neutral,
      rawUpper: upper)
  }

  public static func imageAdjustmentPercent(rawValue: Int, range: UVCScalarRange) -> Int {
    let lower = min(range.minimum, range.maximum)
    let upper = max(range.minimum, range.maximum)
    let neutral = max(lower, min(range.defaultValue, upper))
    let raw = max(lower, min(rawValue, upper))
    guard lower < upper else {
      return imageAdjustmentRange.defaultValue
    }
    if raw == neutral {
      return imageAdjustmentRange.defaultValue
    }
    if raw < neutral {
      return interpolatedPercent(
        raw: raw,
        rawLower: lower,
        rawUpper: neutral,
        percentLower: imageAdjustmentRange.minimum,
        percentUpper: imageAdjustmentRange.defaultValue)
    }
    return interpolatedPercent(
      raw: raw,
      rawLower: neutral,
      rawUpper: upper,
      percentLower: imageAdjustmentRange.defaultValue,
      percentUpper: imageAdjustmentRange.maximum)
  }
}

extension UVCController {
  public func readCameraImageControls() -> CameraImageControlsReadback? {
    var readback = CameraImageControlsReadback()
    for adjustment in OBSBOTImageAdjustment.allCases {
      guard
        let range = try? readProcessingControlRange(adjustment.processingUnitControl),
        let rawValue = try? readProcessingControl(adjustment.processingUnitControl)
      else {
        continue
      }
      let percent = OBSBOTRemoteProtocol.imageAdjustmentPercent(rawValue: rawValue, range: range)
      switch adjustment {
      case .brightness:
        readback.brightness = percent
      case .contrast:
        readback.contrast = percent
      case .saturation:
        readback.saturation = percent
      }
    }
    if let whiteBalanceAuto = try? readProcessingControl(.whiteBalanceTemperatureAuto) {
      readback.whiteBalanceAuto = whiteBalanceAuto != 0
    }
    if let whiteBalanceKelvin = try? readProcessingControl(.whiteBalanceTemperature) {
      readback.whiteBalanceKelvin = whiteBalanceKelvin
    }
    return readback.hasValues ? readback : nil
  }

  public func setCameraImageAdjustment(_ adjustment: OBSBOTImageAdjustment, value: Int) throws {
    do {
      let range = try readProcessingControlRange(adjustment.processingUnitControl)
      let rawValue = OBSBOTRemoteProtocol.imageAdjustmentRawValue(value, range: range)
      try setProcessingControl(adjustment.processingUnitControl, value: rawValue)
      return
    } catch {
      try setOBSBOTImageAdjustment(adjustment, value: value)
    }
  }

  public func setCameraWhiteBalance(mode: OBSBOTWhiteBalanceMode, kelvin: Int = 5_000) throws {
    switch mode {
    case .auto:
      try setProcessingControl(.whiteBalanceTemperatureAuto, value: 1)
    case .manual:
      try setProcessingControl(.whiteBalanceTemperatureAuto, value: 0)
      let range = try? readProcessingControlRange(.whiteBalanceTemperature)
      let clamped =
        clamp(kelvin, to: range) ?? OBSBOTRemoteProtocol.clampedWhiteBalanceKelvin(kelvin)
      try setProcessingControl(.whiteBalanceTemperature, value: clamped)
    }
  }

  public func resetCameraImageSettings() throws {
    let neutral = OBSBOTRemoteProtocol.imageAdjustmentRange.defaultValue
    try setCameraImageAdjustment(.brightness, value: neutral)
    try setCameraImageAdjustment(.contrast, value: neutral)
    try setCameraImageAdjustment(.saturation, value: neutral)
    try setCameraWhiteBalance(mode: .auto)
  }

  public func setOBSBOTImageAdjustment(_ adjustment: OBSBOTImageAdjustment, value: Int) throws {
    let packet = OBSBOTRemoteProtocol.makeImageAdjustmentPacket(
      adjustment,
      value: value,
      sequence: UInt16.random(in: 1...UInt16.max)
    )
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )
  }
}

private func interpolatedRawValue(
  percent: Int,
  percentLower: Int,
  percentUpper: Int,
  rawLower: Int,
  rawUpper: Int
) -> Int {
  guard percentLower != percentUpper else {
    return rawUpper
  }
  let ratio = Double(percent - percentLower) / Double(percentUpper - percentLower)
  return Int((Double(rawLower) + (Double(rawUpper - rawLower) * ratio)).rounded())
}

private func interpolatedPercent(
  raw: Int,
  rawLower: Int,
  rawUpper: Int,
  percentLower: Int,
  percentUpper: Int
) -> Int {
  guard rawLower != rawUpper else {
    return percentUpper
  }
  let ratio = Double(raw - rawLower) / Double(rawUpper - rawLower)
  let percent =
    Int((Double(percentLower) + (Double(percentUpper - percentLower) * ratio)).rounded())
  return OBSBOTRemoteProtocol.clampedImageAdjustmentValue(percent)
}

private func clamp(_ value: Int, to range: UVCScalarRange?) -> Int? {
  guard let range else {
    return nil
  }
  let lower = min(range.minimum, range.maximum)
  let upper = max(range.minimum, range.maximum)
  return max(lower, min(value, upper))
}
