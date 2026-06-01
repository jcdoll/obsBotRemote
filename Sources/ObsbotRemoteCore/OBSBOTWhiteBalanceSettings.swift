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
  public var isManualGain: Bool
  public var blueGain: Int32
  public var redGain: Int32
  public var xabOffset: Int32
  public var ygmOffset: Int32

  public init(
    mode: OBSBOTWhiteBalanceMode,
    kelvin: Int,
    isManualGain: Bool,
    blueGain: Int32,
    redGain: Int32,
    xabOffset: Int32,
    ygmOffset: Int32
  ) {
    self.mode = mode
    self.kelvin = kelvin
    self.isManualGain = isManualGain
    self.blueGain = blueGain
    self.redGain = redGain
    self.xabOffset = xabOffset
    self.ygmOffset = ygmOffset
  }
}

extension OBSBOTRemoteProtocol {
  public static let whiteBalanceKelvinRange = UVCScalarRange(
    minimum: 2_000,
    maximum: 10_000,
    resolution: 100,
    defaultValue: 3_000
  )
  public static let neutralWhiteBalanceOffset: Int32 = 28

  public static func neutralAutoWhiteBalanceSetting() -> OBSBOTWhiteBalanceSetting {
    OBSBOTWhiteBalanceSetting(
      mode: .auto,
      kelvin: 0,
      isManualGain: false,
      blueGain: 0,
      redGain: 0,
      xabOffset: neutralWhiteBalanceOffset,
      ygmOffset: neutralWhiteBalanceOffset
    )
  }

  public static func makeWhiteBalanceSettingPacket(
    _ setting: OBSBOTWhiteBalanceSetting,
    sequence: UInt16
  ) -> [UInt8] {
    makeV3CommandPacket(
      flag: 0x21,
      route: 0x02,
      v3CommandSet: 0x02,
      v3CommandID: 0x00AB,
      payload: whiteBalanceSettingPayload(setting),
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
    guard payload.count >= 28 else {
      throw UVCRequestError.shortRead(
        operation: "OBSBOT white balance payload",
        expected: 28,
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
      kelvin: mode == .auto ? rawKelvin : clampedWhiteBalanceKelvin(rawKelvin),
      isManualGain: payload[8] != 0,
      blueGain: littleEndianInt32(payload[12..<16]),
      redGain: littleEndianInt32(payload[16..<20]),
      xabOffset: littleEndianInt32(payload[20..<24]),
      ygmOffset: littleEndianInt32(payload[24..<28])
    )
  }

  public static func clampedWhiteBalanceKelvin(_ kelvin: Int) -> Int {
    max(whiteBalanceKelvinRange.minimum, min(kelvin, whiteBalanceKelvinRange.maximum))
  }
}

extension UVCController {
  public func setCameraWhiteBalance(
    mode: OBSBOTWhiteBalanceMode,
    kelvin: Int = OBSBOTRemoteProtocol.whiteBalanceKelvinRange.defaultValue
  ) throws {
    let clamped = OBSBOTRemoteProtocol.clampedWhiteBalanceKelvin(kelvin)
    var setting = try readOBSBOTWhiteBalanceSetting()
    setting.mode = mode
    if mode == .manual {
      setting.kelvin = clamped
    }
    try writeOBSBOTWhiteBalanceSetting(setting)
    try waitForOBSBOTWhiteBalance(mode: mode, kelvin: clamped)
  }

  public func resetCameraWhiteBalanceToNeutralAuto() throws {
    try writeOBSBOTWhiteBalanceSetting(OBSBOTRemoteProtocol.neutralAutoWhiteBalanceSetting())
    try waitForOBSBOTWhiteBalance(
      mode: .auto,
      kelvin: OBSBOTRemoteProtocol.whiteBalanceKelvinRange.defaultValue,
      xabOffset: OBSBOTRemoteProtocol.neutralWhiteBalanceOffset,
      ygmOffset: OBSBOTRemoteProtocol.neutralWhiteBalanceOffset
    )
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

  private func writeOBSBOTWhiteBalanceSetting(_ setting: OBSBOTWhiteBalanceSetting) throws {
    let packet = OBSBOTRemoteProtocol.makeWhiteBalanceSettingPacket(
      setting,
      sequence: UInt16.random(in: 1...UInt16.max)
    )
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )
  }

  private func waitForOBSBOTWhiteBalance(
    mode: OBSBOTWhiteBalanceMode,
    kelvin: Int,
    xabOffset: Int32? = nil,
    ygmOffset: Int32? = nil
  ) throws {
    var lastReadback: OBSBOTWhiteBalanceSetting?
    for _ in 0..<20 {
      Thread.sleep(forTimeInterval: 0.05)
      let readback = try readOBSBOTWhiteBalanceSetting()
      lastReadback = readback
      let kelvinMatches = mode == .auto || readback.kelvin == kelvin
      let xabMatches = xabOffset.map { readback.xabOffset == $0 } ?? true
      let ygmMatches = ygmOffset.map { readback.ygmOffset == $0 } ?? true
      if readback.mode == mode && kelvinMatches && xabMatches && ygmMatches {
        return
      }
    }

    let detail =
      lastReadback.map {
        "got mode=\($0.mode) kelvin=\($0.kelvin) xab=\($0.xabOffset) ygm=\($0.ygmOffset)"
      } ?? "no readback"
    throw UVCRequestError.invalidResponse(
      operation: "OBSBOT white balance setting",
      reason: "expected mode=\(mode) kelvin=\(kelvin), \(detail)"
    )
  }
}

private func whiteBalanceSettingPayload(_ setting: OBSBOTWhiteBalanceSetting) -> [UInt8] {
  var payload: [UInt8] = []
  payload.appendLittleEndian(setting.mode.rawValue)
  payload.appendLittleEndian(Int32(setting.kelvin))
  payload.append(setting.isManualGain ? 1 : 0)
  payload.append(contentsOf: [0, 0, 0])
  payload.appendLittleEndian(setting.blueGain)
  payload.appendLittleEndian(setting.redGain)
  payload.appendLittleEndian(setting.xabOffset)
  payload.appendLittleEndian(setting.ygmOffset)
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

  fileprivate mutating func appendLittleEndian(_ value: Int32) {
    appendLittleEndian(UInt32(bitPattern: value))
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
