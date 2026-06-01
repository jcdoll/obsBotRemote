import Foundation

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

public struct OBSBOTWhiteBalanceSetting: Equatable, Sendable {
  public var mode: OBSBOTWhiteBalanceMode
  public var kelvin: Int
}

extension OBSBOTRemoteProtocol {
  public static let whiteBalanceKelvinRange = UVCScalarRange(
    minimum: 2_000,
    maximum: 10_000,
    resolution: 100,
    defaultValue: 5_000
  )

  public static func makeWhiteBalanceSettingPacket(
    mode: OBSBOTWhiteBalanceMode,
    kelvin: Int,
    sequence: UInt16
  ) -> [UInt8] {
    makeV3CommandPacket(
      flag: 0x21,
      route: 0x02,
      v3CommandSet: 0x02,
      v3CommandID: 0x00AB,
      payload: whiteBalanceSettingPayload(mode: mode, kelvin: kelvin),
      sequence: sequence
    )
  }

  public static func makeWhiteBalanceSettingGetPacket(sequence: UInt16) -> [UInt8] {
    makeV3CommandPacket(
      flag: 0x01,
      route: 0x02,
      v3CommandSet: 0x02,
      v3CommandID: 0x00AA,
      payload: [],
      sequence: sequence
    )
  }

  public static func whiteBalanceSetting(fromResponse bytes: [UInt8], sequence: UInt16)
    throws -> OBSBOTWhiteBalanceSetting
  {
    let payload = try whiteBalanceRMResponsePayload(
      from: bytes,
      matchingSequence: sequence,
      commandSet: 0x02,
      commandID: 0x00AA,
      operation: "OBSBOT white balance response")
    guard payload.count >= 8 else {
      throw UVCRequestError.shortRead(
        operation: "OBSBOT white balance payload",
        expected: 8,
        actual: UInt32(payload.count)
      )
    }
    let rawMode = littleEndianUInt32(payload[0..<4])
    let rawKelvin = Int(littleEndianInt32(payload[4..<8]))
    let mode =
      rawMode == OBSBOTWhiteBalanceMode.manual.rawValue
      ? OBSBOTWhiteBalanceMode.manual
      : OBSBOTWhiteBalanceMode.auto
    return OBSBOTWhiteBalanceSetting(
      mode: mode,
      kelvin: clampedWhiteBalanceKelvin(rawKelvin)
    )
  }

  public static func clampedWhiteBalanceKelvin(_ kelvin: Int) -> Int {
    max(whiteBalanceKelvinRange.minimum, min(kelvin, whiteBalanceKelvinRange.maximum))
  }
}

extension UVCController {
  public func setCameraWhiteBalance(mode: OBSBOTWhiteBalanceMode, kelvin: Int = 5_000) throws {
    let clamped = OBSBOTRemoteProtocol.clampedWhiteBalanceKelvin(kelvin)
    let packet = OBSBOTRemoteProtocol.makeWhiteBalanceSettingPacket(
      mode: mode,
      kelvin: clamped,
      sequence: UInt16.random(in: 1...UInt16.max)
    )
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )
    try waitForOBSBOTWhiteBalance(mode: mode, kelvin: clamped)
  }

  public func readOBSBOTWhiteBalanceSetting() throws -> OBSBOTWhiteBalanceSetting {
    let sequence = UInt16.random(in: 1...UInt16.max)
    let packet = OBSBOTRemoteProtocol.makeWhiteBalanceSettingGetPacket(sequence: sequence)
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )

    var lastError: Error?
    for attempt in 0..<50 {
      if attempt > 0 {
        Thread.sleep(forTimeInterval: 0.02)
      }
      do {
        let response = try readExtensionUnitCurrentAllowingShortRead(
          unitID: OBSBOTRemoteProtocol.extensionUnitID,
          selector: OBSBOTRemoteProtocol.commandSelector,
          length: OBSBOTRemoteProtocol.uvcPacketLength
        )
        return try OBSBOTRemoteProtocol.whiteBalanceSetting(
          fromResponse: response,
          sequence: sequence
        )
      } catch {
        lastError = error
      }
    }

    if let error = lastError {
      throw error
    }
    throw UVCRequestError.invalidResponse(
      operation: "OBSBOT white balance response",
      reason: "no response"
    )
  }

  private func waitForOBSBOTWhiteBalance(mode: OBSBOTWhiteBalanceMode, kelvin: Int) throws {
    var lastReadback: OBSBOTWhiteBalanceSetting?
    for _ in 0..<20 {
      Thread.sleep(forTimeInterval: 0.05)
      let readback = try readOBSBOTWhiteBalanceSetting()
      lastReadback = readback
      if readback.mode == mode && (mode == .auto || readback.kelvin == kelvin) {
        return
      }
    }

    let detail =
      lastReadback.map {
        "got mode=\($0.mode) kelvin=\($0.kelvin)"
      } ?? "no readback"
    throw UVCRequestError.invalidResponse(
      operation: "OBSBOT white balance setting",
      reason: "expected mode=\(mode) kelvin=\(kelvin), \(detail)"
    )
  }
}

private func whiteBalanceSettingPayload(
  mode: OBSBOTWhiteBalanceMode,
  kelvin: Int
) -> [UInt8] {
  var payload: [UInt8] = []
  payload.appendLittleEndian(mode.rawValue)
  payload.appendLittleEndian(UInt32(OBSBOTRemoteProtocol.clampedWhiteBalanceKelvin(kelvin)))
  payload.append(0)
  payload.append(contentsOf: [0, 0, 0])
  payload.appendLittleEndian(UInt32(0))
  payload.appendLittleEndian(UInt32(0))
  payload.appendLittleEndian(UInt32(0))
  payload.appendLittleEndian(UInt32(0))
  return payload
}

private func littleEndianUInt32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
  var value: UInt32 = 0
  for (offset, byte) in bytes.prefix(4).enumerated() {
    value |= UInt32(byte) << UInt32(offset * 8)
  }
  return value
}

private func littleEndianInt32(_ bytes: ArraySlice<UInt8>) -> Int32 {
  Int32(bitPattern: littleEndianUInt32(bytes))
}

extension Array where Element == UInt8 {
  fileprivate mutating func appendLittleEndian(_ value: UInt32) {
    append(UInt8(value & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
    append(UInt8((value >> 16) & 0xFF))
    append(UInt8((value >> 24) & 0xFF))
  }
}

private func whiteBalanceRMResponsePayload(
  from bytes: [UInt8],
  matchingSequence sequence: UInt16,
  commandSet expectedCommandSet: UInt8,
  commandID expectedCommandID: UInt16,
  operation: String
) throws -> [UInt8] {
  guard bytes.count >= 16 && bytes[0] == 0xAA && (bytes[1] & 0x03) == 0x01 else {
    throw UVCRequestError.invalidResponse(
      operation: operation,
      reason: "response was not an RM frame"
    )
  }

  let responseSequence = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
  guard responseSequence == sequence else {
    throw UVCRequestError.invalidResponse(
      operation: operation,
      reason: "stale response sequence \(responseSequence), expected \(sequence)"
    )
  }

  let commandSet = bytes[10] & 0x3F
  let commandID = UInt16(bytes[10] >> 6) | (UInt16(bytes[11]) << 2)
  guard commandSet == expectedCommandSet, commandID == expectedCommandID else {
    throw UVCRequestError.invalidResponse(
      operation: operation,
      reason:
        "unexpected command set/id \(formatHex(UInt32(commandSet), width: 2))/\(formatHex(UInt32(commandID), width: 4)), expected \(formatHex(UInt32(expectedCommandSet), width: 2))/\(formatHex(UInt32(expectedCommandID), width: 4))"
    )
  }

  let payloadLength = Int(UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
  guard bytes.count >= 16 + payloadLength else {
    throw UVCRequestError.shortRead(
      operation: "\(operation) payload",
      expected: 16 + payloadLength,
      actual: UInt32(bytes.count)
    )
  }
  return Array(bytes[16..<(16 + payloadLength)])
}
