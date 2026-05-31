import Foundation

public struct OBSBOTTinyGestureStateSnapshot: Equatable, Sendable {
  public var master: Bool
  public var targetSelection: Bool
  public var zoom: Bool
  public var dynamicZoom: Bool
  public var mirror: Bool

  public init(
    master: Bool,
    targetSelection: Bool,
    zoom: Bool,
    dynamicZoom: Bool,
    mirror: Bool
  ) {
    self.master = master
    self.targetSelection = targetSelection
    self.zoom = zoom
    self.dynamicZoom = dynamicZoom
    self.mirror = mirror
  }

  public init() {
    self.init(
      master: false,
      targetSelection: false,
      zoom: false,
      dynamicZoom: false,
      mirror: false)
  }

  public func value(for parameter: OBSBOTTinyGestureParameter) -> Bool? {
    switch parameter {
    case .master:
      master
    case .targetSelection:
      targetSelection
    case .zoom:
      zoom
    case .dynamicZoom:
      dynamicZoom
    case .mirror:
      mirror
    case .record, .snapshot, .rolling:
      nil
    }
  }

  public func matchesHandGestureControls(enabled: Bool) -> Bool {
    master == enabled && targetSelection == enabled && zoom == enabled
      && dynamicZoom == enabled && mirror == enabled
  }
}

extension OBSBOTRemoteProtocol {
  public static func makeTinyGestureParameterGetPacket(
    _ parameter: OBSBOTTinyGestureParameter,
    sequence: UInt16
  ) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x03,
      commandID: 0x007D,
      payload: makeUInt32Payload(parameter.rawValue),
      sequence: sequence
    )
  }

  public static func makeTinyAIStatusGetPacket(sequence: UInt16) -> [UInt8] {
    makeSDKRMCommandPacket(
      commandSet: 0x03,
      commandID: 0x0013,
      payload: [],
      sequence: sequence
    )
  }

  public static func tinyGestureParameterValue(
    fromResponse bytes: [UInt8],
    parameter: OBSBOTTinyGestureParameter,
    matchingSequence sequence: UInt16?
  ) throws -> Bool {
    let payload = try rmResponsePayload(
      from: bytes,
      matchingSequence: sequence,
      commandSet: 0x04,
      commandID: 0x00D2,
      operation: "OBSBOT Tiny gesture response")
    if payload == makeUInt32Payload(parameter.rawValue) {
      throw UVCRequestError.invalidResponse(
        operation: "OBSBOT Tiny gesture response",
        reason: "selector returned the echoed get request"
      )
    }
    return try booleanPayloadValue(payload, operation: "OBSBOT Tiny gesture response")
  }

  public static func tinyGestureState(
    fromAIStatusResponse bytes: [UInt8],
    matchingSequence sequence: UInt16?
  ) throws -> OBSBOTTinyGestureStateSnapshot {
    if !isSDKV3RMFrame(bytes) {
      return try tinyGestureState(
        fromAIStatusPayload: bytes,
        operation: "OBSBOT Tiny AI status response")
    }

    let payload = try rmResponsePayload(
      from: bytes,
      matchingSequence: sequence,
      commandSet: 0x04,
      commandID: 0x0004,
      operation: "OBSBOT Tiny AI status response")

    return try tinyGestureState(
      fromAIStatusPayload: payload,
      operation: "OBSBOT Tiny AI status payload")
  }

  private static func tinyGestureState(
    fromAIStatusPayload payload: [UInt8],
    operation: String
  ) throws -> OBSBOTTinyGestureStateSnapshot {
    if payload.count >= 8 {
      let flags = payload[3]
      let targetSelection = (flags & 0x01) != 0
      let zoom = (flags & 0x02) != 0
      let dynamicZoom = (flags & 0x04) != 0
      let mirror = (flags & 0x40) != 0
      return OBSBOTTinyGestureStateSnapshot(
        master: targetSelection || zoom || dynamicZoom || mirror,
        targetSelection: targetSelection,
        zoom: zoom,
        dynamicZoom: dynamicZoom,
        mirror: mirror)
    }

    throw UVCRequestError.shortRead(
      operation: operation,
      expected: 12,
      actual: UInt32(payload.count)
    )
  }

  private static func rmResponsePayload(
    from bytes: [UInt8],
    matchingSequence sequence: UInt16?,
    commandSet expectedCommandSet: UInt8,
    commandID expectedCommandID: UInt16,
    operation: String
  ) throws -> [UInt8] {
    guard isSDKV3RMFrame(bytes) else {
      throw UVCRequestError.invalidResponse(
        operation: operation,
        reason: "response was not an RM frame"
      )
    }

    if let sequence {
      let responseSequence = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
      guard responseSequence == sequence else {
        throw UVCRequestError.invalidResponse(
          operation: operation,
          reason: "stale response sequence \(responseSequence), expected \(sequence)"
        )
      }
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

  private static func isSDKV3RMFrame(_ bytes: [UInt8]) -> Bool {
    bytes.count >= 16 && bytes[0] == 0xAA && (bytes[1] & 0x03) == 0x01
  }

  private static func booleanPayloadValue(_ payload: [UInt8], operation: String) throws -> Bool {
    guard let value = payload.first else {
      throw UVCRequestError.shortRead(operation: operation, expected: 1, actual: 0)
    }
    guard value == 0 || value == 1 else {
      throw UVCRequestError.invalidResponse(
        operation: operation,
        reason: "first payload byte was \(formatHex(UInt32(value), width: 2)), expected 0 or 1"
      )
    }
    return value == 1
  }
}

extension UVCController {
  public func verifyOBSBOTHandGestureControls(enabled: Bool) throws
    -> OBSBOTTinyGestureStateSnapshot
  {
    let state = try readOBSBOTTinyGestureParameterState()
    guard state.matchesHandGestureControls(enabled: enabled) else {
      throw UVCRequestError.invalidResponse(
        operation: "OBSBOT Tiny hand gesture readback",
        reason:
          "expected all core gesture parameters \(enabled ? "on" : "off"), got master=\(state.master), target=\(state.targetSelection), zoom=\(state.zoom), dynamicZoom=\(state.dynamicZoom), mirror=\(state.mirror)"
      )
    }
    return state
  }

  public func readOBSBOTTinyGestureState() throws -> OBSBOTTinyGestureStateSnapshot {
    try readOBSBOTTinyGestureParameterState()
  }

  public func readOBSBOTTinyGestureParameterState() throws -> OBSBOTTinyGestureStateSnapshot {
    let master = try readOBSBOTTinyGestureParameter(.master)
    let targetSelection = try readOBSBOTTinyGestureParameter(.targetSelection)
    let zoom = try readOBSBOTTinyGestureParameter(.zoom)
    let dynamicZoom = try readOBSBOTTinyGestureParameter(.dynamicZoom)
    let mirror = try readOBSBOTTinyGestureParameter(.mirror)
    return OBSBOTTinyGestureStateSnapshot(
      master: master,
      targetSelection: targetSelection,
      zoom: zoom,
      dynamicZoom: dynamicZoom,
      mirror: mirror)
  }

  public func readOBSBOTTinyAIStatusGestureState() throws -> OBSBOTTinyGestureStateSnapshot {
    let sequence = UInt16.random(in: 1...UInt16.max)
    let packet = OBSBOTRemoteProtocol.makeTinyAIStatusGetPacket(sequence: sequence)
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
        return try OBSBOTRemoteProtocol.tinyGestureState(
          fromAIStatusResponse: response,
          matchingSequence: sequence
        )
      } catch {
        lastError = error
      }
    }

    if let error = lastError {
      throw error
    }
    throw UVCRequestError.invalidResponse(
      operation: "OBSBOT Tiny AI status response",
      reason: "no response"
    )
  }

  public func readOBSBOTTinyGestureParameter(_ parameter: OBSBOTTinyGestureParameter) throws
    -> Bool
  {
    let sequence = UInt16.random(in: 1...UInt16.max)
    let packet = OBSBOTRemoteProtocol.makeTinyGestureParameterGetPacket(
      parameter,
      sequence: sequence
    )
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
        return try OBSBOTRemoteProtocol.tinyGestureParameterValue(
          fromResponse: response,
          parameter: parameter,
          matchingSequence: sequence
        )
      } catch {
        lastError = error
      }
    }

    if let error = lastError {
      throw error
    }
    throw UVCRequestError.invalidResponse(
      operation: "OBSBOT Tiny gesture response",
      reason: "no response"
    )
  }
}
