public enum OBSBOTFieldOfView: Equatable, Sendable, CustomStringConvertible {
  case wide
  case medium
  case narrow
  case unknown(UInt8)

  public init(rawValue: UInt8) {
    switch rawValue {
    case 0:
      self = .wide
    case 1:
      self = .medium
    case 2:
      self = .narrow
    default:
      self = .unknown(rawValue)
    }
  }

  public var rawValue: UInt8? {
    switch self {
    case .wide:
      0
    case .medium:
      1
    case .narrow:
      2
    case .unknown:
      nil
    }
  }

  public var description: String {
    switch self {
    case .wide:
      "wide"
    case .medium:
      "medium"
    case .narrow:
      "narrow"
    case .unknown(let value):
      "unknown(\(formatHex(UInt32(value), width: 2)))"
    }
  }
}

public struct OBSBOTCameraSettingsSnapshot: Equatable, Sendable {
  public var hdrEnabled: Bool
  public var faceAutoExposureEnabled: Bool
  public var faceAutoFocusEnabled: Bool
  public var autoFocusEnabled: Bool
  public var fieldOfView: OBSBOTFieldOfView

  public init(statusBytes bytes: [UInt8]) throws {
    guard bytes.count > 17 else {
      throw UVCRequestError.shortRead(
        operation: "GET_CUR OBSBOT camera settings",
        expected: 18,
        actual: UInt32(bytes.count)
      )
    }
    hdrEnabled = bytes[6] != 0
    faceAutoExposureEnabled = bytes[7] != 0
    faceAutoFocusEnabled = bytes[13] != 0
    autoFocusEnabled = bytes[14] != 0
    fieldOfView = OBSBOTFieldOfView(rawValue: bytes[17])
  }
}

extension OBSBOTRemoteProtocol {
  public static func makeHDRPayload(enabled: Bool) -> [UInt8] {
    makeStatusSelectorPayload(command: 0x01, value: enabled ? 1 : 0)
  }

  public static func makeFaceAEPayload(enabled: Bool) -> [UInt8] {
    makeStatusSelectorPayload(command: 0x03, value: enabled ? 1 : 0)
  }

  public static func makeFieldOfViewPayload(_ fieldOfView: OBSBOTFieldOfView) throws -> [UInt8] {
    guard let rawValue = fieldOfView.rawValue else {
      throw UVCRequestError.unsupportedControl("OBSBOT field of view target \(fieldOfView)")
    }
    return makeStatusSelectorPayload(command: 0x04, value: rawValue)
  }

  private static func makeStatusSelectorPayload(command: UInt8, value: UInt8) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: uvcPacketLength)
    payload[0] = command
    payload[1] = 0x01
    payload[2] = value
    return payload
  }
}

extension UVCController {
  public func readOBSBOTCameraSettings() throws -> OBSBOTCameraSettingsSnapshot {
    let bytes = try readExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      length: OBSBOTRemoteProtocol.uvcPacketLength
    )
    return try OBSBOTCameraSettingsSnapshot(statusBytes: bytes)
  }

  public func setOBSBOTHDR(enabled: Bool) throws {
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      payload: OBSBOTRemoteProtocol.makeHDRPayload(enabled: enabled)
    )
  }

  public func setOBSBOTFaceAutoExposure(enabled: Bool) throws {
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      payload: OBSBOTRemoteProtocol.makeFaceAEPayload(enabled: enabled)
    )
  }

  public func setOBSBOTFaceAutoFocus(enabled: Bool) throws {
    let packet = OBSBOTRemoteProtocol.makeFaceAutoFocusPacket(
      enabled: enabled,
      sequence: UInt16.random(in: 1...UInt16.max)
    )
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.commandSelector,
      payload: packet
    )
  }

  public func setOBSBOTFieldOfView(_ fieldOfView: OBSBOTFieldOfView) throws {
    try setExtensionUnitCurrent(
      unitID: OBSBOTRemoteProtocol.extensionUnitID,
      selector: OBSBOTRemoteProtocol.statusSelector,
      payload: try OBSBOTRemoteProtocol.makeFieldOfViewPayload(fieldOfView)
    )
  }
}
