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
    if let whiteBalance = try? readOBSBOTWhiteBalanceSetting() {
      readback.whiteBalanceAuto = whiteBalance.mode == .auto
      readback.whiteBalanceKelvin = whiteBalance.kelvin
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
