import Foundation
import ObsbotRemoteUSBBridge

public enum UVCRequestError: Error, CustomStringConvertible, Equatable, Sendable {
  case deviceRequestFailed(operation: String, code: Int32, transferred: UInt32)
  case descriptorReadFailed(code: Int32)
  case descriptorTooLarge(required: Int)
  case missingExtensionUnit(UInt8)
  case missingCameraTerminal
  case unsupportedControl(String)
  case shortRead(operation: String, expected: Int, actual: UInt32)

  public var description: String {
    switch self {
    case .deviceRequestFailed(let operation, let code, let transferred):
      "\(operation) failed: \(formatIOReturn(code)) transferred=\(transferred)"
    case .descriptorReadFailed(let code):
      "failed to read USB configuration descriptor: \(formatIOReturn(code))"
    case .descriptorTooLarge(let required):
      "USB configuration descriptor is too large for the probe buffer: \(required) byte(s)"
    case .missingExtensionUnit(let unitID):
      "no UVC extension unit with id \(unitID) was found in the camera configuration descriptor"
    case .missingCameraTerminal:
      "no UVC camera terminal was found in the camera configuration descriptor"
    case .unsupportedControl(let control):
      "camera terminal does not advertise \(control)"
    case .shortRead(let operation, let expected, let actual):
      "\(operation) returned \(actual) byte(s), expected \(expected)"
    }
  }
}

public struct UVCZoomRange: Equatable, Sendable {
  public var minimum: Int
  public var maximum: Int
  public var resolution: Int
  public var defaultValue: Int
}

public struct UVCPanTiltValue: Equatable, Sendable {
  public var pan: Int32
  public var tilt: Int32
}

public struct UVCPanTiltRange: Equatable, Sendable {
  public var minimum: UVCPanTiltValue
  public var maximum: UVCPanTiltValue
  public var resolution: UVCPanTiltValue
  public var defaultValue: UVCPanTiltValue
}

public final class UVCController {
  public var vendorID: UInt16
  public var productID: UInt16

  public init(vendorID: UInt16 = 0x3564, productID: UInt16 = 0xFF02) {
    self.vendorID = vendorID
    self.productID = productID
  }

  public func probe() throws -> UVCProbe {
    try UVCDescriptorParser.parseConfiguration(readConfigurationDescriptor())
  }

  public func readZoom() throws -> Int {
    try readZoom(request: UVCGetRequest.current, operation: "GET_CUR zoom-abs")
  }

  public func readZoomRange() throws -> UVCZoomRange {
    UVCZoomRange(
      minimum: try readZoom(request: UVCGetRequest.minimum, operation: "GET_MIN zoom-abs"),
      maximum: try readZoom(request: UVCGetRequest.maximum, operation: "GET_MAX zoom-abs"),
      resolution: try readZoom(request: UVCGetRequest.resolution, operation: "GET_RES zoom-abs"),
      defaultValue: try readZoom(request: UVCGetRequest.defaultValue, operation: "GET_DEF zoom-abs")
    )
  }

  public func setZoom(_ value: Int) throws {
    let terminal = try cameraTerminal(requiring: .zoomAbsolute)
    let clamped = max(0, min(value, Int(UInt16.max)))
    var payload = [
      UInt8(clamped & 0xFF),
      UInt8((clamped >> 8) & 0xFF),
    ]
    try deviceRequest(
      operation: "SET_CUR zoom-abs",
      requestType: 0x21,
      request: 0x01,
      value: UInt16(UVCCameraTerminalControl.zoomAbsolute.rawValue) << 8,
      index: controlIndex(for: terminal),
      payload: &payload,
      expectedLength: payload.count
    )
  }

  public func readPanTilt() throws -> (pan: Int32, tilt: Int32) {
    let value = try readPanTilt(request: UVCGetRequest.current, operation: "GET_CUR pan-tilt-abs")
    return (pan: value.pan, tilt: value.tilt)
  }

  public func readPanTiltRange() throws -> UVCPanTiltRange {
    UVCPanTiltRange(
      minimum: try readPanTilt(request: UVCGetRequest.minimum, operation: "GET_MIN pan-tilt-abs"),
      maximum: try readPanTilt(request: UVCGetRequest.maximum, operation: "GET_MAX pan-tilt-abs"),
      resolution: try readPanTilt(
        request: UVCGetRequest.resolution, operation: "GET_RES pan-tilt-abs"),
      defaultValue: try readPanTilt(
        request: UVCGetRequest.defaultValue, operation: "GET_DEF pan-tilt-abs")
    )
  }

  private func readZoom(request: UInt8, operation: String) throws -> Int {
    let terminal = try cameraTerminal(requiring: .zoomAbsolute)
    var payload = [UInt8](repeating: 0, count: 2)
    try deviceRequest(
      operation: operation,
      requestType: 0xA1,
      request: request,
      value: UInt16(UVCCameraTerminalControl.zoomAbsolute.rawValue) << 8,
      index: controlIndex(for: terminal),
      payload: &payload,
      expectedLength: payload.count
    )
    return Int(UInt16(payload[0]) | (UInt16(payload[1]) << 8))
  }

  private func readPanTilt(request: UInt8, operation: String) throws -> UVCPanTiltValue {
    let terminal = try cameraTerminal(requiring: .panTiltAbsolute)
    var payload = [UInt8](repeating: 0, count: 8)
    try deviceRequest(
      operation: operation,
      requestType: 0xA1,
      request: request,
      value: UInt16(UVCCameraTerminalControl.panTiltAbsolute.rawValue) << 8,
      index: controlIndex(for: terminal),
      payload: &payload,
      expectedLength: payload.count
    )
    return UVCPanTiltValue(
      pan: Int32(littleEndianBytes: payload[0..<4]),
      tilt: Int32(littleEndianBytes: payload[4..<8])
    )
  }

  public func setPanTilt(pan: Int32, tilt: Int32) throws {
    let terminal = try cameraTerminal(requiring: .panTiltAbsolute)
    var payload: [UInt8] = []
    payload.appendLittleEndian(pan)
    payload.appendLittleEndian(tilt)
    try deviceRequest(
      operation: "SET_CUR pan-tilt-abs",
      requestType: 0x21,
      request: 0x01,
      value: UInt16(UVCCameraTerminalControl.panTiltAbsolute.rawValue) << 8,
      index: controlIndex(for: terminal),
      payload: &payload,
      expectedLength: payload.count
    )
  }

  public func readExtensionUnitInfo(unitID: UInt8, selector: UInt8) throws -> UInt8 {
    let unit = try extensionUnit(unitID: unitID)
    var payload = [UInt8](repeating: 0, count: 1)
    try deviceRequest(
      operation: "GET_INFO xu unit=\(unitID) selector=\(selector)",
      requestType: 0xA1,
      request: 0x86,
      value: UInt16(selector) << 8,
      index: controlIndex(for: unit),
      payload: &payload,
      expectedLength: payload.count
    )
    return payload[0]
  }

  public func readExtensionUnitLength(unitID: UInt8, selector: UInt8) throws -> Int {
    let unit = try extensionUnit(unitID: unitID)
    var payload = [UInt8](repeating: 0, count: 2)
    try deviceRequest(
      operation: "GET_LEN xu unit=\(unitID) selector=\(selector)",
      requestType: 0xA1,
      request: 0x85,
      value: UInt16(selector) << 8,
      index: controlIndex(for: unit),
      payload: &payload,
      expectedLength: payload.count
    )
    return Int(UInt16(payload[0]) | (UInt16(payload[1]) << 8))
  }

  public func readExtensionUnitCurrent(unitID: UInt8, selector: UInt8, length: Int? = nil) throws
    -> [UInt8]
  {
    let unit = try extensionUnit(unitID: unitID)
    let resolvedLength = try length ?? readExtensionUnitLength(unitID: unitID, selector: selector)
    var payload = [UInt8](repeating: 0, count: resolvedLength)
    try deviceRequest(
      operation: "GET_CUR xu unit=\(unitID) selector=\(selector)",
      requestType: 0xA1,
      request: 0x81,
      value: UInt16(selector) << 8,
      index: controlIndex(for: unit),
      payload: &payload,
      expectedLength: payload.count
    )
    return payload
  }

  public func setExtensionUnitCurrent(unitID: UInt8, selector: UInt8, payload: [UInt8]) throws {
    let unit = try extensionUnit(unitID: unitID)
    var mutablePayload = payload
    try deviceRequest(
      operation: "SET_CUR xu unit=\(unitID) selector=\(selector)",
      requestType: 0x21,
      request: 0x01,
      value: UInt16(selector) << 8,
      index: controlIndex(for: unit),
      payload: &mutablePayload,
      expectedLength: mutablePayload.count
    )
  }

  public func readOBSBOTRunStatus() throws -> OBSBOTRunStatus {
    let bytes = try readExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      length: OBSBOTRemoteProtocol.uvcPacketLength
    )
    guard bytes.count > 9 else {
      throw UVCRequestError.shortRead(
        operation: "GET_CUR OBSBOT status",
        expected: 10,
        actual: UInt32(bytes.count)
      )
    }
    return OBSBOTRunStatus(rawValue: bytes[9])
  }

  public func readOBSBOTAIMode() throws -> OBSBOTAIMode {
    let bytes = try readExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      length: OBSBOTRemoteProtocol.uvcPacketLength
    )
    guard bytes.count > 28 else {
      throw UVCRequestError.shortRead(
        operation: "GET_CUR OBSBOT AI mode",
        expected: 29,
        actual: UInt32(bytes.count)
      )
    }
    return OBSBOTAIMode(statusMode: bytes[24], statusSubMode: bytes[28])
  }

  public func setOBSBOTRunStatus(_ status: OBSBOTRunStatus) throws {
    let packet = try OBSBOTRemoteProtocol.makeDevRunStatusPacket(
      status,
      sequence: UInt16.random(in: 1...UInt16.max)
    )
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )
  }

  public func setOBSBOTAIMode(_ mode: OBSBOTAIMode) throws {
    let payload = try OBSBOTRemoteProtocol.makeAIModePayload(mode)
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      payload: payload
    )
  }

  public func toggleOBSBOTRunStatus() throws -> (previous: OBSBOTRunStatus, next: OBSBOTRunStatus) {
    let previous = try readOBSBOTRunStatus()
    let next: OBSBOTRunStatus = previous == .run ? .sleep : .run
    try setOBSBOTRunStatus(next)
    return (previous, next)
  }

  public func toggleOBSBOTAIMode(_ target: OBSBOTAIMode) throws -> (
    previous: OBSBOTAIMode, next: OBSBOTAIMode
  ) {
    let previous = try readOBSBOTAIMode()
    let next: OBSBOTAIMode = previous == target ? .off : target
    try setOBSBOTAIMode(next)
    return (previous, next)
  }

  private func cameraTerminal(requiring control: UVCCameraTerminalControl) throws
    -> UVCCameraTerminal
  {
    guard let terminal = try probe().primaryCameraTerminal else {
      throw UVCRequestError.missingCameraTerminal
    }
    guard terminal.supports(control) else {
      throw UVCRequestError.unsupportedControl(control.displayName)
    }
    return terminal
  }

  private func extensionUnit(unitID: UInt8) throws -> UVCExtensionUnit {
    guard let unit = try probe().extensionUnits.first(where: { $0.unitID == unitID }) else {
      throw UVCRequestError.missingExtensionUnit(unitID)
    }
    return unit
  }

  private func controlIndex(for terminal: UVCCameraTerminal) -> UInt16 {
    (UInt16(terminal.terminalID) << 8) | UInt16(terminal.interfaceNumber)
  }

  private func controlIndex(for unit: UVCExtensionUnit) -> UInt16 {
    (UInt16(unit.unitID) << 8) | UInt16(unit.interfaceNumber)
  }

  private func readConfigurationDescriptor() throws -> Data {
    var buffer = [UInt8](repeating: 0, count: 65_535)
    let capacity = buffer.count
    var length = 0
    let result = buffer.withUnsafeMutableBufferPointer { pointer in
      ORUSBGetConfigurationDescriptor(
        vendorID,
        productID,
        0,
        pointer.baseAddress,
        capacity,
        &length
      )
    }
    guard result == 0 else {
      if result == -536_870_194 {
        throw UVCRequestError.descriptorTooLarge(required: length)
      }
      throw UVCRequestError.descriptorReadFailed(code: result)
    }
    return Data(buffer.prefix(length))
  }

  private func deviceRequest(
    operation: String,
    requestType: UInt8,
    request: UInt8,
    value: UInt16,
    index: UInt16,
    payload: inout [UInt8],
    expectedLength: Int
  ) throws {
    var transferred: UInt32 = 0
    let payloadLength = UInt16(payload.count)
    let result = payload.withUnsafeMutableBufferPointer { pointer in
      ORUSBDeviceRequest(
        vendorID,
        productID,
        requestType,
        request,
        value,
        index,
        pointer.baseAddress,
        payloadLength,
        &transferred
      )
    }
    guard result == 0 else {
      throw UVCRequestError.deviceRequestFailed(
        operation: operation,
        code: result,
        transferred: transferred
      )
    }
    guard transferred == UInt32(expectedLength) else {
      throw UVCRequestError.shortRead(
        operation: operation,
        expected: expectedLength,
        actual: transferred
      )
    }
  }
}

private enum UVCGetRequest {
  static let current: UInt8 = 0x81
  static let minimum: UInt8 = 0x82
  static let maximum: UInt8 = 0x83
  static let resolution: UInt8 = 0x84
  static let defaultValue: UInt8 = 0x87
}

extension Array where Element == UInt8 {
  fileprivate mutating func appendLittleEndian(_ value: Int32) {
    let raw = UInt32(bitPattern: value)
    append(UInt8(raw & 0xFF))
    append(UInt8((raw >> 8) & 0xFF))
    append(UInt8((raw >> 16) & 0xFF))
    append(UInt8((raw >> 24) & 0xFF))
  }
}

extension Int32 {
  fileprivate init(littleEndianBytes bytes: ArraySlice<UInt8>) {
    let raw = bytes.enumerated().reduce(UInt32(0)) { partial, element in
      partial | (UInt32(element.element) << UInt32(element.offset * 8))
    }
    self = Int32(bitPattern: raw)
  }
}

private func formatIOReturn(_ code: Int32) -> String {
  let unsigned = UInt32(bitPattern: code)
  return "0x" + String(unsigned, radix: 16, uppercase: true)
}
