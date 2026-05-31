import Foundation

extension UVCController {
  public func readProcessingControl(_ control: UVCProcessingUnitControl) throws -> Int {
    try readProcessingControl(
      control,
      request: UVCGetRequest.current,
      operation: "GET_CUR \(control.displayName)"
    )
  }

  public func readProcessingControlRange(_ control: UVCProcessingUnitControl) throws
    -> UVCScalarRange
  {
    UVCScalarRange(
      minimum: try readProcessingControl(
        control, request: UVCGetRequest.minimum, operation: "GET_MIN \(control.displayName)"),
      maximum: try readProcessingControl(
        control, request: UVCGetRequest.maximum, operation: "GET_MAX \(control.displayName)"),
      resolution: try readProcessingControl(
        control, request: UVCGetRequest.resolution, operation: "GET_RES \(control.displayName)"),
      defaultValue: try readProcessingControl(
        control, request: UVCGetRequest.defaultValue, operation: "GET_DEF \(control.displayName)")
    )
  }

  public func setProcessingControl(_ control: UVCProcessingUnitControl, value: Int) throws {
    guard control.isScalarLabControl else {
      throw UVCRequestError.unsupportedControl("\(control.displayName) scalar lab write")
    }
    let unit = try processingUnit(requiring: control)
    let range = control.isBooleanControl ? nil : try? readProcessingControlRange(control)
    let clamped = control.isBooleanControl ? value : clamp(value, to: range)
    var payload = processingPayload(for: control, value: clamped)
    try deviceRequest(
      operation: "SET_CUR \(control.displayName)",
      requestType: 0x21,
      request: 0x01,
      value: UInt16(control.rawValue) << 8,
      index: controlIndex(for: unit),
      payload: &payload,
      expectedLength: payload.count
    )
  }

  private func readProcessingControl(
    _ control: UVCProcessingUnitControl,
    request: UInt8,
    operation: String
  ) throws -> Int {
    guard control.isScalarLabControl else {
      throw UVCRequestError.unsupportedControl("\(control.displayName) scalar lab read")
    }
    let unit = try processingUnit(requiring: control)
    var payload = [UInt8](repeating: 0, count: control.payloadLength)
    try deviceRequest(
      operation: operation,
      requestType: 0xA1,
      request: request,
      value: UInt16(control.rawValue) << 8,
      index: controlIndex(for: unit),
      payload: &payload,
      expectedLength: payload.count
    )
    return processingValue(for: control, payload: payload)
  }
}

private func clamp(_ value: Int, to range: UVCScalarRange?) -> Int {
  guard let range else {
    return value
  }
  let lower = min(range.minimum, range.maximum)
  let upper = max(range.minimum, range.maximum)
  return max(lower, min(value, upper))
}

private func processingPayload(for control: UVCProcessingUnitControl, value: Int) -> [UInt8] {
  if control.payloadLength == 1 {
    return [UInt8(max(0, min(value, Int(UInt8.max))))]
  }
  if control.isSigned {
    let raw = UInt16(bitPattern: Int16(max(Int(Int16.min), min(value, Int(Int16.max)))))
    return [UInt8(raw & 0xFF), UInt8((raw >> 8) & 0xFF)]
  }
  let raw = UInt16(max(0, min(value, Int(UInt16.max))))
  return [UInt8(raw & 0xFF), UInt8((raw >> 8) & 0xFF)]
}

private func processingValue(for control: UVCProcessingUnitControl, payload: [UInt8]) -> Int {
  guard payload.count > 1 else {
    return Int(payload.first ?? 0)
  }
  let raw = UInt16(payload[0]) | (UInt16(payload[1]) << 8)
  if control.isSigned {
    return Int(Int16(bitPattern: raw))
  }
  return Int(raw)
}
